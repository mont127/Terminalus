import AppKit
import Quartz
import SwiftUI
import TerminalusCore

/// NSOutlineView subclass: keyboard shortcuts, context menus and Quick Look support.
final class TreeOutlineView: NSOutlineView, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    weak var controller: FileTreeController?

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        let row = self.row(at: p)
        guard row >= 0, let node = item(atRow: row) as? FileNode, !node.isPlaceholder else { return nil }
        if !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        return controller?.contextMenu(for: node)
    }

    override func keyDown(with event: NSEvent) {
        guard let controller else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 49: // space
            controller.toggleQuickLook()
        case 36, 76: // return
            if let n = controller.selectedNode { controller.performDoubleClick(on: n) }
        case 53: // escape
            controller.model?.workspace?.focusedSession?.focusTerminal()
        default:
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c", let n = controller.selectedNode {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(n.path, forType: .string)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    // Quick Look
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { controller?.selectedNode == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        controller?.selectedNode.map { $0.url as NSURL }
    }
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown {
            keyDown(with: event)
            panel.reloadData()
            return true
        }
        return false
    }
}

/// Selection / current-directory highlight drawn with theme colors.
final class TreeRowView: NSTableRowView {
    var accent: NSColor = .controlAccentColor
    var isCwd = false
    var cornerRadius: CGFloat = 5

    var selectionColor: NSColor = NSColor.labelColor.withAlphaComponent(0.1)

    override func drawSelection(in dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 6, dy: 0.5)
        (isEmphasized ? accent.withAlphaComponent(0.22) : selectionColor).setFill()
        NSBezierPath(roundedRect: r, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isCwd, !isSelected else { return }
        let r = bounds.insetBy(dx: 6, dy: 0.5)
        accent.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: r, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

/// Icon + name + detail + git badge.
final class FileCellView: NSTableCellView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")
    private let emoji = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        for v in [icon, label, detail, badge, emoji] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        label.lineBreakMode = .byTruncatingMiddle
        label.cell?.truncatesLastVisibleLine = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.setContentCompressionResistancePriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        badge.alignment = .center
        icon.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            emoji.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
            emoji.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 6),
            detail.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.leadingAnchor.constraint(equalTo: detail.trailingAnchor, constant: 4),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 12),
        ])
        textField = label
        imageView = icon
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(_ node: FileNode, model: FileTreeModel, theme: ResolvedTheme, settings: TreeSettings, uiDesign: UIFontDesign) {
        let size = CGFloat(settings.fontSize)
        let isCwd = node.path == model.cwd
        let onPath = !isCwd && Paths.isAncestor(node.path, of: model.cwd) && node.isExpandable
        let weight: NSFont.Weight = isCwd ? .semibold : (onPath ? .medium : .regular)
        let baseFont = NSFont.systemFont(ofSize: size, weight: weight)
        let font = uiDesign == .monospaced ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            : (baseFont.fontDescriptor.withDesign(uiDesign.nsDesign).flatMap { NSFont(descriptor: $0, size: size) } ?? baseFont)
        label.font = font
        detail.font = NSFont.monospacedDigitSystemFont(ofSize: max(8, size - 2), weight: .regular)
        badge.font = NSFont.monospacedSystemFont(ofSize: max(8, size - 2), weight: .bold)

        switch node.kind {
        case .loading:
            label.stringValue = "Loading…"
            label.textColor = theme.secondaryText.nsColor
            setIcon(nil, emoji: "", color: nil)
            detail.stringValue = ""
            badge.stringValue = ""
            return
        case .message(let m):
            label.stringValue = m
            label.textColor = theme.secondaryText.nsColor.withAlphaComponent(0.8)
            setIcon(m.contains("Permission") ? NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) : nil,
                    emoji: "", color: theme.secondaryText.nsColor)
            detail.stringValue = ""
            badge.stringValue = ""
            return
        case .more(let n):
            label.stringValue = "Show \(n) more…"
            label.textColor = theme.accent.nsColor
            setIcon(NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: nil), emoji: "", color: theme.accent.nsColor)
            detail.stringValue = ""
            badge.stringValue = ""
            return
        case .entry:
            break
        }

        label.stringValue = node.name + (node.isSymlink ? " ↪" : "")
        let git = settings.gitBadges ? model.gitStatus?.state(for: node.path) : nil
        var textColor = theme.text
        if node.isHiddenFile { textColor = theme.secondaryText }
        if isCwd { textColor = theme.accent }
        if let g = git, g != .ignored { textColor = TreeStyle.gitColor(g, theme: theme).mix(textColor, 0.35) }
        label.textColor = textColor.nsColor

        switch settings.iconStyle {
        case .none:
            setIcon(nil, emoji: "", color: nil)
        case .emoji:
            setIcon(nil, emoji: TreeStyle.emoji(for: node), color: nil)
        case .system:
            setIcon(TreeStyle.systemIcon(for: node), emoji: "", color: nil)
        case .symbols:
            let (sym, c) = TreeStyle.symbol(for: node, theme: theme, isCwd: isCwd)
            let neutral = node.isExpandable ? theme.secondaryText.withAlpha(0.9) : theme.secondaryText.withAlpha(0.7)
            let color = settings.coloredIcons ? c : (isCwd ? theme.accent : neutral)
            setIcon(NSImage(systemSymbolName: sym, accessibilityDescription: nil), emoji: "", color: color.nsColor)
        }

        var parts: [String] = []
        if settings.showSizes, !node.isDirectory, let s = node.size { parts.append(Fmt.bytes(Double(s), decimals: 0)) }
        if settings.showItemCounts, node.isExpandable, let c = node.allChildren?.count { parts.append("\(c)") }
        if settings.showDates, let d = node.modified { parts.append(TreeStyle.dateFormatter.string(from: d)) }
        detail.stringValue = parts.joined(separator: "  ")
        detail.textColor = theme.secondaryText.nsColor

        if let g = git, g != .ignored {
            badge.stringValue = g.letter
            badge.textColor = TreeStyle.gitColor(g, theme: theme).nsColor
        } else {
            badge.stringValue = ""
        }
    }

    private func setIcon(_ image: NSImage?, emoji e: String, color: NSColor?) {
        icon.image = image
        icon.contentTintColor = color
        icon.isHidden = image == nil && e.isEmpty
        emoji.stringValue = e
        emoji.isHidden = e.isEmpty
        if !e.isEmpty { icon.isHidden = false; icon.image = nil }
    }
}

extension UIFontDesign {
    var nsDesign: NSFontDescriptor.SystemDesign {
        switch self {
        case .system: .default
        case .rounded: .rounded
        case .monospaced: .monospaced
        case .serif: .serif
        }
    }
}

enum TreeStyle {
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yy-MM-dd"
        return f
    }()

    static func gitColor(_ s: GitFileState, theme: ResolvedTheme) -> RGBA {
        switch s {
        case .modified: theme.warning
        case .added: theme.success
        case .deleted, .conflicted: theme.danger
        case .renamed: theme.accent
        case .untracked: theme.accent2
        case .ignored: theme.secondaryText
        }
    }

    private static let codeExt: Set<String> = ["js", "jsx", "ts", "tsx", "py", "rb", "go", "rs", "c", "cc", "cpp", "h", "hpp", "m", "mm",
                                               "java", "kt", "cs", "php", "lua", "sh", "zsh", "bash", "fish", "pl", "r", "scala", "dart", "zig", "vue", "svelte", "html", "css", "scss"]
    private static let dataExt: Set<String> = ["json", "yaml", "yml", "toml", "plist", "xml", "ini", "conf", "cfg", "env", "lock", "csv", "sql"]
    private static let textExt: Set<String> = ["md", "txt", "rtf", "log", "rst", "tex"]
    private static let imageExt: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "bmp", "tiff", "ico", "icns"]
    private static let videoExt: Set<String> = ["mp4", "mov", "mkv", "avi", "webm", "m4v"]
    private static let audioExt: Set<String> = ["mp3", "wav", "aac", "flac", "m4a", "ogg", "aiff"]
    private static let archiveExt: Set<String> = ["zip", "tar", "gz", "tgz", "xz", "bz2", "7z", "rar", "dmg", "pkg", "iso", "zst"]

    static func symbol(for node: FileNode, theme: ResolvedTheme, isCwd: Bool) -> (String, RGBA) {
        let p = theme.chartPalette
        if node.isPackage { return (node.fileExtension == "app" ? "app.fill" : "shippingbox.fill", p[4]) }
        if node.isExpandable {
            if node.name == ".git" { return ("arrow.triangle.branch", theme.danger) }
            if node.isSymlink { return ("folder.fill.badge.gearshape", theme.accent2.withAlpha(0.8)) }
            return (isCwd ? "folder.fill" : "folder.fill", isCwd ? theme.accent : theme.accent2)
        }
        let e = node.fileExtension
        let n = node.name.lowercased()
        if e == "swift" { return ("swift", RGBA(r: 1, g: 0.45, b: 0.25)) }
        if n == "dockerfile" || n.hasPrefix("docker-compose") { return ("shippingbox", p[4]) }
        if n == "makefile" || n == "cmakelists.txt" { return ("hammer.fill", p[3]) }
        if n.hasPrefix(".git") { return ("arrow.triangle.branch", theme.danger) }
        if n.hasPrefix("readme") { return ("book.fill", p[2]) }
        if n.hasPrefix("license") || n.hasPrefix("licence") { return ("checkmark.seal.fill", p[3]) }
        if codeExt.contains(e) { return ("chevron.left.forwardslash.chevron.right", p[2]) }
        if dataExt.contains(e) { return ("curlybraces", p[3]) }
        if textExt.contains(e) { return ("doc.text.fill", theme.text.withAlpha(0.75)) }
        if imageExt.contains(e) { return ("photo.fill", p[6]) }
        if videoExt.contains(e) { return ("film.fill", p[5]) }
        if audioExt.contains(e) { return ("waveform", p[7]) }
        if archiveExt.contains(e) { return ("archivebox.fill", p[4]) }
        if e == "pdf" { return ("doc.richtext.fill", theme.danger) }
        if e.isEmpty, FileManager.default.isExecutableFile(atPath: node.path) { return ("terminal.fill", theme.success) }
        return ("doc.fill", theme.secondaryText)
    }

    static func emoji(for node: FileNode) -> String {
        if node.isPackage { return node.fileExtension == "app" ? "🚀" : "📦" }
        if node.isExpandable { return node.isSymlink ? "🔗" : "📁" }
        let e = node.fileExtension
        switch e {
        case "swift": return "🕊️"
        case "py": return "🐍"
        case "rs": return "🦀"
        case "go": return "🐹"
        case "js", "ts", "jsx", "tsx": return "⚡️"
        case "rb": return "💎"
        case "md", "txt", "rtf": return "📝"
        case "json", "yaml", "yml", "toml", "plist", "xml": return "⚙️"
        case "pdf": return "📕"
        case "sh", "zsh", "bash", "fish": return "🐚"
        default:
            if imageExt.contains(e) { return "🖼️" }
            if videoExt.contains(e) { return "🎬" }
            if audioExt.contains(e) { return "🎵" }
            if archiveExt.contains(e) { return "🗜️" }
            return "📄"
        }
    }

    private static let iconCache = NSCache<NSString, NSImage>()

    static func systemIcon(for node: FileNode) -> NSImage {
        let key = (node.isExpandable ? "dir:" : "ext:") + (node.isPackage ? node.path : node.fileExtension) as NSString
        if let img = iconCache.object(forKey: key) { return img }
        let img = NSWorkspace.shared.icon(forFile: node.path)
        img.size = NSSize(width: 16, height: 16)
        iconCache.setObject(img, forKey: key)
        return img
    }
}

/// Bridges FileTreeModel to NSOutlineView (data source, delegate, actions, menus).
@MainActor
final class FileTreeController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    weak var model: FileTreeModel?
    weak var outline: TreeOutlineView?
    private var programmaticExpansion = 0

    private var theme: ResolvedTheme { AppState.shared.uiTheme }
    private var settings: TreeSettings { AppState.shared.settings.tree }

    func attach(_ outline: TreeOutlineView) {
        self.outline = outline
        outline.controller = self
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(clicked(_:))
        outline.doubleAction = #selector(doubleClicked(_:))
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)
        outline.setDraggingSourceOperationMask(.copy, forLocal: true)
        applyStyle()
        outline.reloadData()
        if let m = model {
            expand(m.root)
            m.reveal(m.cwd, select: true)
        }
    }

    func applyStyle() {
        guard let o = outline else { return }
        o.rowHeight = CGFloat(settings.rowHeight)
        o.indentationPerLevel = CGFloat(settings.indentation)
        o.needsDisplay = true
    }

    // MARK: Commands from the model

    func reloadAll() {
        guard let o = outline, let model else { return }
        o.reloadData()
        // Restore expansion (reloadData may drop it for re-created items).
        programmaticExpansion += 1
        o.expandItem(model.root)
        for p in model.expandedPaths.sorted(by: { $0.count < $1.count }) {
            if let n = model.node(at: p), o.row(forItem: n) >= 0 { o.expandItem(n) }
        }
        programmaticExpansion -= 1
    }

    func reloadChildren(of node: FileNode) {
        guard let o = outline else { return }
        if node === model?.root || o.row(forItem: node) >= 0 {
            programmaticExpansion += 1
            o.reloadItem(node, reloadChildren: true)
            programmaticExpansion -= 1
        }
    }

    func refreshVisibleRows() {
        guard let o = outline else { return }
        let rows = o.rows(in: o.visibleRect)
        guard rows.length > 0 else { return }
        o.reloadData(forRowIndexes: IndexSet(integersIn: rows.location..<(rows.location + rows.length)), columnIndexes: IndexSet(integer: 0))
        for r in rows.location..<(rows.location + rows.length) {
            if let rv = o.rowView(atRow: r, makeIfNecessary: false) as? TreeRowView, let n = o.item(atRow: r) as? FileNode {
                rv.isCwd = n.path == model?.cwd
                rv.accent = theme.accent.nsColor
                rv.needsDisplay = true
            }
        }
    }

    func expand(_ node: FileNode) {
        guard let o = outline else { return }
        programmaticExpansion += 1
        o.expandItem(node)
        programmaticExpansion -= 1
    }

    func collapse(_ node: FileNode) {
        guard let o = outline else { return }
        programmaticExpansion += 1
        o.collapseItem(node)
        programmaticExpansion -= 1
    }

    func isExpanded(_ node: FileNode) -> Bool { outline?.isItemExpanded(node) ?? false }

    func scrollTo(_ node: FileNode, select: Bool) {
        guard let o = outline else { return }
        let row = o.row(forItem: node)
        guard row >= 0 else { return }
        if select { o.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        refreshVisibleRows()
        // Center the row if it is off screen.
        let rect = o.rect(ofRow: row)
        if !o.visibleRect.contains(rect), let clip = o.enclosingScrollView?.contentView {
            let y = max(0, rect.midY - clip.bounds.height / 2)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = AppState.shared.settings.appearance.animateUI ? 0.2 : 0
                clip.animator().setBoundsOrigin(NSPoint(x: 0, y: y))
            }
        }
        refreshVisibleRows()
    }

    func focusOutline() {
        guard let o = outline else { return }
        o.window?.makeFirstResponder(o)
        if o.selectedRow < 0, let m = model, let n = m.node(at: m.cwd) ?? Optional(m.root) {
            let r = o.row(forItem: n)
            if r >= 0 { o.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false) }
        }
    }

    var selectedNode: FileNode? {
        guard let o = outline else { return nil }
        let row = o.clickedRow >= 0 ? o.clickedRow : o.selectedRow
        guard row >= 0, let n = o.item(atRow: row) as? FileNode, !n.isPlaceholder else { return nil }
        return n
    }

    // MARK: Data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let model else { return 0 }
        guard let node = item as? FileNode else { return 1 }
        return node.displayChildren.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? FileNode else { return model!.root }
        let kids = node.displayChildren
        return index < kids.count ? kids[index] : node.loadingPlaceholder
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileNode)?.isExpandable ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let n = item as? FileNode, !n.isPlaceholder else { return nil }
        return n.url as NSURL
    }

    // MARK: Delegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode, let model else { return nil }
        let id = NSUserInterfaceItemIdentifier("FileCell")
        let cell = (outlineView.makeView(withIdentifier: id, owner: nil) as? FileCellView) ?? {
            let c = FileCellView(frame: .zero)
            c.identifier = id
            return c
        }()
        cell.configure(node, model: model, theme: theme, settings: settings, uiDesign: AppState.shared.settings.appearance.uiFontDesign)
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let rv = TreeRowView()
        rv.accent = theme.accent.nsColor
        rv.selectionColor = theme.text.withAlpha(0.09).nsColor
        rv.isCwd = (item as? FileNode)?.path == model?.cwd
        rv.cornerRadius = CGFloat(min(6, AppState.shared.settings.appearance.cornerRadius / 2))
        return rv
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let n = item as? FileNode else { return false }
        if case .more = n.kind, let parent = n.parent {
            model?.showMore(in: parent)
            return false
        }
        return !n.isPlaceholder
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let n = notification.userInfo?["NSObject"] as? FileNode else { return }
        model?.didExpand(n, byUser: programmaticExpansion == 0)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let n = notification.userInfo?["NSObject"] as? FileNode else { return }
        model?.didCollapse(n)
    }

    // MARK: Actions

    @objc private func clicked(_ sender: Any?) {
        guard let o = outline, o.clickedRow >= 0, let n = o.item(atRow: o.clickedRow) as? FileNode, !n.isPlaceholder else { return }
        perform(settings.singleClick, on: n)
    }

    @objc private func doubleClicked(_ sender: Any?) {
        guard let o = outline, o.clickedRow >= 0, let n = o.item(atRow: o.clickedRow) as? FileNode, !n.isPlaceholder else { return }
        performDoubleClick(on: n)
    }

    func performDoubleClick(on n: FileNode) {
        perform(n.isExpandable ? settings.doubleClickFolder : settings.doubleClickFile, on: n)
    }

    func perform(_ action: TreeAction, on n: FileNode) {
        let ws = model?.workspace
        let session = ws?.focusedSession
        let dir = n.isExpandable ? n.path : (n.path as NSString).deletingLastPathComponent
        switch action {
        case .none, .select:
            break
        case .toggleExpand:
            guard n.isExpandable, let o = outline else { return }
            if o.isItemExpanded(n) { o.collapseItem(n) } else { o.expandItem(n) }
        case .insertPath:
            session?.insertPath(n.path)
        case .cd:
            session?.cd(dir)
        case .open:
            NSWorkspace.shared.open(n.url)
        case .openInEditor:
            if n.isExpandable || n.isPackage {
                session?.cd(dir)
            } else {
                ws?.openInEditor([n.path])
            }
        case .quickLook:
            if let o = outline {
                let r = o.row(forItem: n)
                if r >= 0 { o.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false) }
                o.window?.makeFirstResponder(o)
            }
            toggleQuickLook()
        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([n.url])
        case .newTab:
            ws?.newTab(cwd: dir)
        }
    }

    func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
            panel.reloadData()
        }
    }

    func contextMenu(for n: FileNode) -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ symbol: String, _ block: @escaping () -> Void) {
            let item = ClosureMenuItem(title: title, symbol: symbol, block: block)
            menu.addItem(item)
        }
        let dir = n.isExpandable ? n.path : (n.path as NSString).deletingLastPathComponent
        let ws = model?.workspace
        add("cd Here", "arrow.right.circle") { ws?.focusedSession?.cd(dir) }
        add("Insert Path", "text.cursor") { ws?.focusedSession?.insertPath(n.path) }
        add("New Tab Here", "plus.rectangle.on.rectangle") { ws?.newTab(cwd: dir) }
        add("Split Right Here", "rectangle.split.2x1") { ws?.split(.horizontal, cwd: dir) }
        add("Split Down Here", "rectangle.split.1x2") { ws?.split(.vertical, cwd: dir) }
        menu.addItem(.separator())
        if !n.isExpandable {
            add("Open in Editor", "chevron.left.forwardslash.chevron.right") { ws?.openInEditor([n.path]) }
        }
        add("Open", "arrow.up.forward.app") { NSWorkspace.shared.open(n.url) }
        add("Quick Look", "eye") { [weak self] in self?.perform(.quickLook, on: n) }
        add("Reveal in Finder", "folder") { NSWorkspace.shared.activateFileViewerSelecting([n.url]) }
        menu.addItem(.separator())
        add("Copy Path", "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(n.path, forType: .string)
        }
        add("Copy Name", "character.cursor.ibeam") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(n.name, forType: .string)
        }
        menu.addItem(.separator())
        let hidden = AppState.shared.settings.tree.showHidden
        add(hidden ? "Hide Hidden Files" : "Show Hidden Files", hidden ? "eye.slash" : "eye") {
            AppState.shared.settingsStore.update { $0.tree.showHidden.toggle() }
        }
        add("Refresh", "arrow.clockwise") { [weak self] in
            guard let self, let model = self.model else { return }
            if let node = model.node(at: dir) {
                node.allChildren = nil
                model.load(node)
            }
        }
        return menu
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let block: () -> Void

    init(title: String, symbol: String, block: @escaping () -> Void) {
        self.block = block
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() { block() }
}

/// SwiftUI wrapper around the outline view.
struct FileTreeView: NSViewRepresentable {
    let model: FileTreeModel
    /// Changing these re-applies styling.
    var styleKey: Int

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        let outline = TreeOutlineView()
        outline.headerView = nil
        outline.backgroundColor = .clear
        outline.style = .plain
        outline.selectionHighlightStyle = .regular
        outline.allowsMultipleSelection = false
        outline.floatsGroupRows = false
        outline.autoresizesOutlineColumn = false
        outline.focusRingType = .none
        outline.intercellSpacing = NSSize(width: 0, height: 0)
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        col.resizingMask = .autoresizingMask
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        scroll.documentView = outline
        model.controller.attach(outline)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if context.coordinator.styleKey != styleKey {
            context.coordinator.styleKey = styleKey
            model.controller.applyStyle()
            model.controller.reloadAll()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(styleKey: styleKey) }

    final class Coordinator {
        var styleKey: Int
        init(styleKey: Int) { self.styleKey = styleKey }
    }
}
