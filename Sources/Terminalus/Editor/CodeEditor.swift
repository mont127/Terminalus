import AppKit
import TerminalusCore

/// The editor's text view: code-friendly editing (auto-indent, soft tabs, bracket pairs, comment toggle)
/// and a current-line highlight.
final class CodeTextView: NSTextView {
    weak var controller: CodeEditorController?
    var indentUnit = "    "
    var autoIndent = true
    var autoClose = true
    var highlightLine = true
    var currentLineColor: NSColor = .clear

    private static let pairs: [Character: Character] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`"]

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard highlightLine, selectedRange().length == 0, let lm = layoutManager, let tc = textContainer else { return }
        let ns = string as NSString
        let loc = min(selectedRange().location, ns.length)
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        var glyphRange = lm.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        if glyphRange.length == 0 { glyphRange.length = 0 }
        var lineRect: NSRect
        if loc == ns.length && (ns.length == 0 || ns.character(at: ns.length - 1) == 10) {
            lineRect = lm.extraLineFragmentRect
        } else {
            lineRect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        }
        guard lineRect.height > 0 else { return }
        lineRect.origin.x = 0
        lineRect.size.width = bounds.width
        lineRect.origin.y += textContainerOrigin.y
        currentLineColor.setFill()
        lineRect.fill()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if highlightLine { needsDisplay = true }
    }

    // MARK: Editing helpers

    private var ns: NSString { string as NSString }

    private func replace(_ range: NSRange, with text: String, select: NSRange? = nil) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        if let select { setSelectedRange(select) }
    }

    private func leadingWhitespace(ofLineAt loc: Int) -> String {
        let line = ns.substring(with: ns.lineRange(for: NSRange(location: loc, length: 0)))
        return String(line.prefix { $0 == " " || $0 == "\t" })
    }

    override func insertNewline(_ sender: Any?) {
        guard autoIndent, let lang = controller?.language else { return super.insertNewline(sender) }
        let sel = selectedRange()
        var indent = leadingWhitespace(ofLineAt: sel.location)
        // Don't carry indentation past the cursor if it sits inside the leading whitespace.
        let lineStart = ns.lineRange(for: NSRange(location: sel.location, length: 0)).location
        if sel.location - lineStart < indent.count { indent = String(indent.prefix(sel.location - lineStart)) }
        let before: Character? = sel.location > 0 ? Character(UnicodeScalar(ns.character(at: sel.location - 1)) ?? " ") : nil
        let after: Character? = sel.location + sel.length < ns.length
            ? Character(UnicodeScalar(ns.character(at: sel.location + sel.length)) ?? " ") : nil
        let opensBlock = before.map { "{[(".contains($0) } ?? false
            || (before == ":" && (lang == .python || lang == .yaml))
        if opensBlock, let b = before, let a = after, CodeTextView.pairs[b] == a, b != "\"", b != "'" {
            let text = "\n" + indent + indentUnit + "\n" + indent
            replace(sel, with: text, select: NSRange(location: sel.location + 1 + indent.count + indentUnit.count, length: 0))
            return
        }
        let text = "\n" + indent + (opensBlock ? indentUnit : "")
        replace(sel, with: text, select: NSRange(location: sel.location + (text as NSString).length, length: 0))
    }

    override func insertTab(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length > 0, ns.substring(with: sel).contains("\n") {
            shiftLines(outdent: false)
            return
        }
        if indentUnit.hasPrefix("\t") { return super.insertTab(sender) }
        let lineStart = ns.lineRange(for: NSRange(location: sel.location, length: 0)).location
        let col = sel.location - lineStart
        let width = max(1, indentUnit.count)
        let spaces = String(repeating: " ", count: width - (col % width))
        replace(sel, with: spaces, select: NSRange(location: sel.location + spaces.count, length: 0))
    }

    override func insertBacktab(_ sender: Any?) {
        shiftLines(outdent: true)
    }

    /// Indents or outdents every line touched by the selection.
    func shiftLines(outdent: Bool) {
        let sel = selectedRange()
        let range = ns.lineRange(for: sel)
        let text = ns.substring(with: range)
        var lines = text.components(separatedBy: "\n")
        let trailingEmpty = text.hasSuffix("\n")
        if trailingEmpty { lines.removeLast() }
        let width = max(1, indentUnit.count)
        lines = lines.map { line in
            if outdent {
                if line.hasPrefix("\t") { return String(line.dropFirst()) }
                let n = min(width, line.prefix { $0 == " " }.count)
                return String(line.dropFirst(n))
            }
            return line.isEmpty ? line : indentUnit + line
        }
        let result = lines.joined(separator: "\n") + (trailingEmpty ? "\n" : "")
        replace(range, with: result, select: NSRange(location: range.location, length: (result as NSString).length - (trailingEmpty ? 1 : 0)))
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard autoClose, let s = string as? String, s.count == 1, let ch = s.first else {
            return super.insertText(string, replacementRange: replacementRange)
        }
        let sel = selectedRange()
        let next: Character? = sel.location < ns.length ? Character(UnicodeScalar(ns.character(at: sel.location)) ?? " ") : nil
        // Typing a closer that is already there just steps over it.
        if ")]}\"'`".contains(ch), sel.length == 0, next == ch {
            setSelectedRange(NSRange(location: sel.location + 1, length: 0))
            return
        }
        if let close = CodeTextView.pairs[ch] {
            let prev: Character? = sel.location > 0 ? Character(UnicodeScalar(ns.character(at: sel.location - 1)) ?? " ") : nil
            let isQuote = ch == "\"" || ch == "'" || ch == "`"
            let nextIsWord = next.map { $0.isLetter || $0.isNumber || $0 == "_" } ?? false
            let prevIsWord = prev.map { $0.isLetter || $0.isNumber || $0 == "_" } ?? false
            if sel.length > 0 {
                // Wrap the selection.
                let inner = ns.substring(with: sel)
                replace(sel, with: String(ch) + inner + String(close), select: NSRange(location: sel.location + 1, length: sel.length))
                return
            }
            if !nextIsWord && !(isQuote && prevIsWord) {
                replace(sel, with: String(ch) + String(close), select: NSRange(location: sel.location + 1, length: 0))
                return
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length == 0, sel.location > 0, sel.location < ns.length {
            let a = Character(UnicodeScalar(ns.character(at: sel.location - 1)) ?? " ")
            let b = Character(UnicodeScalar(ns.character(at: sel.location)) ?? " ")
            if autoClose, CodeTextView.pairs[a] == b {
                replace(NSRange(location: sel.location - 1, length: 2), with: "", select: NSRange(location: sel.location - 1, length: 0))
                return
            }
        }
        // Soft tabs: delete back to the previous tab stop inside leading whitespace.
        if sel.length == 0, !indentUnit.hasPrefix("\t"), sel.location > 0 {
            let lineStart = ns.lineRange(for: NSRange(location: sel.location, length: 0)).location
            let before = ns.substring(with: NSRange(location: lineStart, length: sel.location - lineStart))
            if !before.isEmpty, before.allSatisfy({ $0 == " " }) {
                let width = max(1, indentUnit.count)
                let n = before.count % width == 0 ? width : before.count % width
                replace(NSRange(location: sel.location - n, length: n), with: "", select: NSRange(location: sel.location - n, length: 0))
                return
            }
        }
        super.deleteBackward(sender)
    }

    func toggleComment() {
        guard let prefix = controller?.language.lineComment else {
            NSSound.beep()
            return
        }
        let sel = selectedRange()
        let range = ns.lineRange(for: sel)
        let text = ns.substring(with: range)
        var lines = text.components(separatedBy: "\n")
        let trailing = text.hasSuffix("\n")
        if trailing { lines.removeLast() }
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allCommented = !nonEmpty.isEmpty && nonEmpty.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }
        let minIndent = nonEmpty.map { $0.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
        lines = lines.map { line in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            if allCommented {
                guard let r = line.range(of: prefix) else { return line }
                var out = line
                out.removeSubrange(r)
                if out[r.lowerBound...].hasPrefix(" ") { out.remove(at: r.lowerBound) }
                return out
            }
            let idx = line.index(line.startIndex, offsetBy: min(minIndent, line.count))
            return String(line[..<idx]) + prefix + " " + String(line[idx...])
        }
        let result = lines.joined(separator: "\n") + (trailing ? "\n" : "")
        replace(range, with: result, select: NSRange(location: range.location, length: (result as NSString).length - (trailing ? 1 : 0)))
    }
}

/// Line numbers in the gutter.
final class LineNumberRuler: NSRulerView {
    weak var textView: CodeTextView?
    var numberColor: NSColor = .secondaryLabelColor
    var currentColor: NSColor = .labelColor
    var font: NSFont = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    /// Offsets where each line starts, maintained by the controller.
    var lineStarts: [Int] = [0]

    init(textView: CodeTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isOpaque: Bool { false }

    /// Only the numbers: no ruler background or border.
    override func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)
    }

    func updateThickness() {
        let digits = max(3, String(lineStarts.count).count)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
        let w = ceil(CGFloat(digits) * digitWidth + 22)
        if abs(ruleThickness - w) > 0.5 {
            ruleThickness = w
            // The clip view must move over when the gutter changes width.
            scrollView?.tile()
        }
    }

    private func lineIndex(for offset: Int) -> Int {
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let visible = tv.visibleRect
        let glyphs = lm.glyphRange(forBoundingRect: visible, in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let ns = tv.string as NSString
        let currentLine = lineIndex(for: min(tv.selectedRange().location, ns.length))
        var idx = lineIndex(for: chars.location)
        let yOffset = convert(NSPoint.zero, from: tv).y + tv.textContainerOrigin.y
        let attrs: (Bool) -> [NSAttributedString.Key: Any] = { current in
            [.font: self.font, .foregroundColor: current ? self.currentColor : self.numberColor]
        }
        while idx < lineStarts.count {
            let start = lineStarts[idx]
            if start > NSMaxRange(chars) && start != ns.length { break }
            var lineRect: NSRect
            if start >= ns.length {
                lineRect = lm.extraLineFragmentRect
                if lineRect.height == 0 { break }
            } else {
                let g = lm.glyphIndexForCharacter(at: start)
                lineRect = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
            }
            let label = "\(idx + 1)" as NSString
            let a = attrs(idx == currentLine)
            let size = label.size(withAttributes: a)
            let y = yOffset + lineRect.minY + (lineRect.height - size.height) / 2
            label.draw(at: NSPoint(x: ruleThickness - size.width - 10, y: y), withAttributes: a)
            if start >= ns.length { break }
            idx += 1
        }
    }
}

/// Owns one document's text system and views; applies settings, theme and syntax colors.
@MainActor
final class CodeEditorController: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
    let scrollView = NSScrollView()
    let textView: CodeTextView
    let ruler: LineNumberRuler
    weak var document: EditorDocument?
    var language: Language = .plain
    private let storage = NSTextStorage()
    private let undo = UndoManager()
    private var font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private var italicFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private var boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
    private var theme: ResolvedTheme?
    private var suppressChanges = false
    private let highlightDebouncer = Debouncer(delay: 0.12)
    private var highlightingEnabled = true
    private var appliedKey: String?

    init(text: String) {
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        lm.addTextContainer(container)
        lm.allowsNonContiguousLayout = true
        textView = CodeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        ruler = LineNumberRuler(textView: textView, scrollView: scrollView)
        super.init()
        storage.setAttributedString(NSAttributedString(string: text))
        storage.delegate = self
        textView.controller = self
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        updateLineStarts()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
    }

    var text: String { storage.string }

    // MARK: Appearance

    func apply(settings: EditorSettings, terminal: TerminalSettings, theme: ResolvedTheme) {
        let key = "\(settings.tabWidth)|\(settings.insertSpaces)|\(settings.wordWrap)|\(settings.showLineNumbers)|\(settings.highlightCurrentLine)|\(settings.autoIndent)|\(settings.autoCloseBrackets)|\(settings.syntaxHighlighting)|\(settings.fontSize ?? -1)|\(terminal.font.family)|\(terminal.font.size)|\(terminal.font.weight)|\(terminal.font.lineSpacing)|\(theme.id)|\(theme.accent.hex)"
        guard key != appliedKey else { return }
        appliedKey = key
        self.theme = theme
        let size = settings.fontSize ?? terminal.font.size
        font = FontResolver.terminalFont(family: terminal.font.family, size: size, weight: terminal.font.weight)
        italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        textView.font = font
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = CGFloat(max(1, terminal.font.lineSpacing))
        let tabWidth = CGFloat(max(1, settings.tabWidth)) * (" " as NSString).size(withAttributes: [.font: font]).width
        para.defaultTabInterval = tabWidth
        para.tabStops = []
        textView.defaultParagraphStyle = para
        textView.typingAttributes = [.font: font, .foregroundColor: theme.foreground.nsColor, .paragraphStyle: para]
        textView.insertionPointColor = theme.cursor.nsColor
        textView.selectedTextAttributes = [.backgroundColor: theme.selection.nsColor]
        textView.indentUnit = settings.insertSpaces ? String(repeating: " ", count: max(1, settings.tabWidth)) : "\t"
        textView.autoIndent = settings.autoIndent
        textView.autoClose = settings.autoCloseBrackets
        textView.highlightLine = settings.highlightCurrentLine
        textView.currentLineColor = theme.text.withAlpha(0.045).nsColor
        highlightingEnabled = settings.syntaxHighlighting
        scrollView.rulersVisible = settings.showLineNumbers
        ruler.font = NSFont.monospacedDigitSystemFont(ofSize: max(9, size - 2), weight: .regular)
        ruler.numberColor = theme.secondaryText.withAlpha(0.55).nsColor
        ruler.currentColor = theme.text.withAlpha(0.9).nsColor
        ruler.updateThickness()
        // Wrapping
        if settings.wordWrap {
            textView.isHorizontallyResizable = false
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
            scrollView.hasHorizontalScroller = false
        } else {
            textView.isHorizontallyResizable = true
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            scrollView.hasHorizontalScroller = true
        }
        storage.beginEditing()
        storage.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        rehighlight()
        ruler.needsDisplay = true
        textView.needsDisplay = true
    }

    // MARK: Highlighting

    private func color(_ kind: TokenKind, _ t: ResolvedTheme) -> NSColor {
        let a = t.ansi
        switch kind {
        case .keyword: return a[5].nsColor
        case .type: return a[6].nsColor
        case .string: return a[2].nsColor
        case .number: return a[3].nsColor
        case .comment: return a[8].nsColor
        case .function: return a[4].nsColor
        case .attribute: return a[11].nsColor
        case .constant: return a[9].mix(a[3], 0.5).nsColor
        case .variable: return a[1].mix(t.foreground, 0.3).nsColor
        case .property: return a[1].mix(t.foreground, 0.25).nsColor
        case .tag: return a[1].nsColor
        case .heading: return t.accent.nsColor
        case .emphasis: return t.foreground.nsColor
        }
    }

    func rehighlight() {
        highlight(range: nil)
    }

    /// Highlights `range` (expanded to whole lines), or the whole document when it is small enough.
    private func highlight(range: NSRange?) {
        guard let theme else { return }
        let full = NSRange(location: 0, length: storage.length)
        var r = full
        if let range {
            r = (storage.string as NSString).lineRange(for: range)
        } else if storage.length > 400_000 {
            // Big files: only what is on screen (plus margin).
            r = visibleCharacterRange(margin: 4000)
        }
        let tokens = highlightingEnabled ? SyntaxHighlighter.tokens(in: storage.string, language: language, range: r) : []
        storage.beginEditing()
        storage.addAttributes([.font: font, .foregroundColor: theme.foreground.nsColor], range: r)
        for tok in tokens {
            let rr = NSIntersectionRange(tok.range, r)
            guard rr.length > 0 else { continue }
            storage.addAttribute(.foregroundColor, value: color(tok.kind, theme), range: rr)
            switch tok.kind {
            case .comment: storage.addAttribute(.font, value: italicFont, range: rr)
            case .heading, .emphasis: storage.addAttribute(.font, value: boldFont, range: rr)
            default: break
            }
        }
        storage.endEditing()
    }

    private func visibleCharacterRange(margin: Int) -> NSRange {
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return NSRange(location: 0, length: 0) }
        let glyphs = lm.glyphRange(forBoundingRect: textView.visibleRect, in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let start = max(0, chars.location - margin)
        let end = min(storage.length, NSMaxRange(chars) + margin)
        return NSRange(location: start, length: end - start)
    }

    // MARK: Text changes

    nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated {
            guard !suppressChanges else { return }
            // Colors for the edited lines right away; the whole file (multi-line strings/comments) shortly after.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let len = self.storage.length
                let start = min(editedRange.location, len)
                self.highlight(range: NSRange(location: start, length: min(editedRange.length, len - start)))
                self.highlightDebouncer.call { [weak self] in
                    Task { @MainActor in self?.rehighlight() }
                }
            }
        }
    }

    func textDidChange(_ notification: Notification) {
        updateLineStarts()
        guard !suppressChanges else { return }
        document?.textDidChange()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        let sel = textView.selectedRange()
        let loc = min(sel.location, storage.length)
        var lo = 0, hi = ruler.lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if ruler.lineStarts[mid] <= loc { lo = mid } else { hi = mid - 1 }
        }
        document?.selectionDidChange(line: lo + 1, column: loc - ruler.lineStarts[lo] + 1, length: sel.length)
        ruler.needsDisplay = true
    }

    func undoManager(for view: NSTextView) -> UndoManager? { undo }

    private func updateLineStarts() {
        var starts = [0]
        let s = storage.string.utf16
        var i = 0
        for u in s {
            i += 1
            if u == 10 { starts.append(i) }
        }
        ruler.lineStarts = starts
        ruler.updateThickness()
        ruler.needsDisplay = true
    }

    // MARK: Commands

    func replaceAll(_ text: String, keepSelection: Bool) {
        let sel = textView.selectedRange()
        suppressChanges = true
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
        storage.endEditing()
        suppressChanges = false
        undo.removeAllActions()
        updateLineStarts()
        rehighlight()
        if keepSelection {
            let loc = min(sel.location, storage.length)
            textView.setSelectedRange(NSRange(location: loc, length: 0))
        }
    }

    func goTo(line: Int) {
        let idx = min(max(1, line), ruler.lineStarts.count) - 1
        let loc = min(ruler.lineStarts[idx], storage.length)
        textView.setSelectedRange(NSRange(location: loc, length: 0))
        textView.scrollRangeToVisible(NSRange(location: loc, length: 0))
        // Put the line a third of the way down instead of at the very edge.
        if let lm = textView.layoutManager, storage.length > 0 {
            let g = lm.glyphIndexForCharacter(at: min(loc, max(0, storage.length - 1)))
            let rect = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
            let clip = scrollView.contentView
            let y = max(0, rect.minY - clip.bounds.height / 3)
            clip.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(clip)
        }
        textView.window?.makeFirstResponder(textView)
    }

    func promptGoToLine() {
        let alert = NSAlert()
        alert.messageText = "Go to Line"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "Line number (1–\(ruler.lineStarts.count))"
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn, let n = Int(field.stringValue.trimmingCharacters(in: .whitespaces)) {
            goTo(line: n)
        }
    }
}
