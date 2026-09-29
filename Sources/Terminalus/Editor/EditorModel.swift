import AppKit
import Observation
import TerminalusCore

/// One open file in the built-in editor.
@MainActor
@Observable
final class EditorDocument: Identifiable {
    let id = UUID().uuidString
    private(set) var url: URL?
    private(set) var language: Language
    var isDirty = false
    var cursorLine = 1
    var cursorColumn = 1
    var selectionLength = 0
    var symbols: [OutlineSymbol] = []
    /// The file changed on disk while the buffer had unsaved edits.
    var externalChange = false
    private(set) var usesCRLF = false

    @ObservationIgnored let controller: CodeEditorController
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var lastSavedData: Data?

    var name: String { url?.lastPathComponent ?? "Untitled" }
    var path: String? { url?.path }

    init(url: URL?, text: String) {
        self.url = url
        let first = text.prefix(200).split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        language = Language.detect(fileName: url?.lastPathComponent ?? "", firstLine: first)
        let crlf = text.contains("\r\n")
        usesCRLF = crlf
        controller = CodeEditorController(text: crlf ? text.replacingOccurrences(of: "\r\n", with: "\n") : text)
        controller.document = self
        controller.language = language
        lastSavedData = url.flatMap { try? Data(contentsOf: $0) }
        refreshSymbols()
        watch()
    }

    enum LoadError: LocalizedError {
        case binary(String), tooLarge(String), unreadable(String)
        var errorDescription: String? {
            switch self {
            case .binary(let n): "\(n) looks like a binary file."
            case .tooLarge(let n): "\(n) is too large for the built-in editor."
            case .unreadable(let n): "\(n) can't be read (permission denied?)."
            }
        }
    }

    /// Reads a file for editing. Missing files open as new, empty buffers (like nano/vim do).
    static func load(_ url: URL) throws -> EditorDocument {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return EditorDocument(url: url, text: "") }
        let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        if size > 25_000_000 { throw LoadError.tooLarge(url.lastPathComponent) }
        guard let data = try? Data(contentsOf: url) else { throw LoadError.unreadable(url.lastPathComponent) }
        if data.prefix(8000).contains(0) { throw LoadError.binary(url.lastPathComponent) }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return EditorDocument(url: url, text: text)
    }

    // MARK: Saving

    func save() throws {
        guard let url else { throw CocoaError(.fileWriteUnknown) }
        var text = controller.text
        let settings = AppState.shared.settings.editor
        if settings.trimTrailingWhitespace {
            text = text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> Substring in
                    var l = line
                    while let last = l.last, last == " " || last == "\t" { l = l.dropLast() }
                    return l
                }
                .joined(separator: "\n")
        }
        if settings.ensureTrailingNewline, !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        // Keep the buffer identical to what goes to disk (minus line-ending conversion).
        if text != controller.text { controller.replaceAll(text, keepSelection: true) }
        if usesCRLF { text = text.replacingOccurrences(of: "\n", with: "\r\n") }
        let data = Data(text.utf8)
        // Keep the file's permissions (e.g. the executable bit) across the atomic replace.
        let perms = (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber
        lastSavedData = data
        try data.write(to: url, options: .atomic)
        if let perms { try? FileManager.default.setAttributes([.posixPermissions: perms], ofItemAtPath: url.path) }
        isDirty = false
        externalChange = false
        watch()
    }

    func saveAs(_ newURL: URL) throws {
        url = newURL
        language = Language.detect(fileName: newURL.lastPathComponent)
        controller.language = language
        controller.rehighlight()
        try save()
        refreshSymbols()
    }

    func reloadFromDisk() {
        guard let url, let data = try? Data(contentsOf: url) else { return }
        lastSavedData = data
        let text = String(data: data, encoding: .utf8) ?? ""
        controller.replaceAll(usesCRLF ? text.replacingOccurrences(of: "\r\n", with: "\n") : text, keepSelection: true)
        isDirty = false
        externalChange = false
        refreshSymbols()
    }

    private func watch() {
        watcher?.stop()
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        watcher = FileWatcher(url: url) { [weak self] in
            Task { @MainActor in self?.fileChangedOnDisk() }
        }
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    private func fileChangedOnDisk() {
        guard let url, let data = try? Data(contentsOf: url), data != lastSavedData else { return }
        if isDirty {
            externalChange = true
        } else {
            reloadFromDisk()
        }
    }

    // MARK: Callbacks from the controller

    @ObservationIgnored private let symbolDebouncer = Debouncer(delay: 0.4)

    func textDidChange() {
        if !isDirty { isDirty = true }
        symbolDebouncer.call { [weak self] in
            Task { @MainActor in self?.refreshSymbols() }
        }
    }

    func refreshSymbols() {
        let s = OutlineExtractor.symbols(in: controller.text, language: language)
        if s != symbols { symbols = s }
    }

    func selectionDidChange(line: Int, column: Int, length: Int) {
        if cursorLine != line { cursorLine = line }
        if cursorColumn != column { cursorColumn = column }
        if selectionLength != length { selectionLength = length }
    }
}

/// The IDE state of one tab: open documents plus the shells waiting for them (`nano file` blocks until
/// the file is closed, exactly like the real editor would).
@MainActor
@Observable
final class EditorSession {
    private(set) var documents: [EditorDocument] = []
    var activeID: String?
    var message: String?

    struct Request {
        let fifo: String
        let command: String
        let sessionID: String
        var documentIDs: Set<String>
    }

    @ObservationIgnored private(set) var requests: [Request] = []
    @ObservationIgnored weak var workspace: Workspace?
    @ObservationIgnored weak var tab: TabModel?

    init(workspace: Workspace, tab: TabModel) {
        self.workspace = workspace
        self.tab = tab
    }

    var active: EditorDocument? { documents.first { $0.id == activeID } ?? documents.last }

    // MARK: Opening

    @discardableResult
    func open(_ target: EditTarget?) -> EditorDocument? {
        if let target {
            let url = URL(fileURLWithPath: target.path).standardizedFileURL
            if let existing = documents.first(where: { $0.url?.standardizedFileURL == url }) {
                activate(existing)
                if target.line > 0 { existing.controller.goTo(line: target.line) }
                return existing
            }
            do {
                let doc = try EditorDocument.load(url)
                add(doc)
                if target.line > 0 {
                    DispatchQueue.main.async { doc.controller.goTo(line: target.line) }
                }
                return doc
            } catch {
                message = error.localizedDescription
                return nil
            }
        }
        let doc = EditorDocument(url: nil, text: "")
        add(doc)
        return doc
    }

    private func add(_ doc: EditorDocument) {
        documents.append(doc)
        activate(doc)
    }

    func activate(_ doc: EditorDocument) {
        activeID = doc.id
        focusActive()
    }

    func focusActive() {
        guard let doc = active else { return }
        DispatchQueue.main.async {
            doc.controller.textView.window?.makeFirstResponder(doc.controller.textView)
        }
    }

    func addRequest(fifo: String, command: String, sessionID: String, documentIDs: Set<String>) {
        requests.append(Request(fifo: fifo, command: command, sessionID: sessionID, documentIDs: documentIDs))
    }

    func requestFor(_ doc: EditorDocument) -> Request? {
        requests.first { $0.documentIDs.contains(doc.id) }
    }

    // MARK: Saving

    /// Saves the document, asking for a location when it has none. Returns false if cancelled/failed.
    @discardableResult
    func save(_ doc: EditorDocument, forceChooseLocation: Bool = false) -> Bool {
        if doc.url == nil || forceChooseLocation {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = doc.name == "Untitled" ? "untitled.txt" : doc.name
            if let cwd = workspace?.focusedSession?.cwd { panel.directoryURL = URL(fileURLWithPath: cwd) }
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            do {
                try doc.saveAs(url)
                return true
            } catch {
                showError("Couldn't save \(url.lastPathComponent)", error)
                return false
            }
        }
        do {
            try doc.save()
            return true
        } catch {
            showError("Couldn't save \(doc.name)", error)
            return false
        }
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        let ns = error as NSError
        var info = error.localizedDescription
        if ns.code == NSFileWriteNoPermissionError { info += "\nThe file isn't writable by you — use `sudo` with the real editor (e.g. `sudo nano`)." }
        alert.informativeText = info
        alert.runModal()
    }

    // MARK: Closing

    /// Closes a document (asking about unsaved changes). Returns false if the user cancelled.
    @discardableResult
    func close(_ doc: EditorDocument, exitCode: String = "0") -> Bool {
        if doc.isDirty {
            let alert = NSAlert()
            alert.messageText = "Save changes to \(doc.name)?"
            alert.informativeText = "Your changes will be lost if you don't save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Don't Save")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                if !save(doc) { return false }
            case .alertThirdButtonReturn:
                break
            default:
                return false
            }
        }
        doc.stopWatching()
        documents.removeAll { $0.id == doc.id }
        if activeID == doc.id { activeID = documents.last?.id }
        finish(docID: doc.id, reply: exitCode)
        if documents.isEmpty {
            workspace?.closeEditor(for: tab)
        } else {
            focusActive()
        }
        return true
    }

    /// Closes everything; returns false if the user cancelled.
    func closeAll() -> Bool {
        for doc in documents.reversed() where doc.isDirty {
            activate(doc)
            if !close(doc) { return false }
        }
        for doc in documents.reversed() { close(doc) }
        return true
    }

    /// Hands a request back to the real editor ("Open in nano" / "Open in vim").
    func fallBack(_ doc: EditorDocument) {
        guard let req = requestFor(doc) else { return }
        for id in req.documentIDs {
            if let d = documents.first(where: { $0.id == id }), !d.isDirty {
                d.stopWatching()
                documents.removeAll { $0.id == id }
            }
        }
        requests.removeAll { $0.fifo == req.fifo }
        EditReply.send("fallback", to: req.fifo)
        workspace?.sessions[req.sessionID]?.editorRequestFinished()
        if activeID.map({ id in !documents.contains { $0.id == id } }) ?? true { activeID = documents.last?.id }
        if documents.isEmpty {
            workspace?.closeEditor(for: tab)
            workspace?.focus(sessionID: req.sessionID)
        }
    }

    private func finish(docID: String, reply: String) {
        for i in requests.indices.reversed() {
            requests[i].documentIDs.remove(docID)
            if requests[i].documentIDs.isEmpty {
                let req = requests.remove(at: i)
                EditReply.send(reply, to: req.fifo)
                workspace?.sessions[req.sessionID]?.editorRequestFinished()
            }
        }
    }

    /// The shell stopped waiting (Ctrl-C): forget its request but keep the files open.
    func dropRequests(for sessionID: String) {
        requests.removeAll { $0.sessionID == sessionID }
    }

    /// Unblocks every waiting shell (used when the window closes).
    func releaseAll() {
        for req in requests { EditReply.send("0", to: req.fifo) }
        requests.removeAll()
        documents.forEach { $0.stopWatching() }
    }

    // MARK: Run

    func runActive() {
        guard let doc = active, let ws = workspace, let tab else { return }
        if doc.isDirty || doc.url == nil {
            guard save(doc) else { return }
        }
        guard let url = doc.url else { return }
        let ext = url.pathExtension.lowercased()
        let templates = AppState.shared.settings.editor.runCommands
        guard let template = templates[ext] ?? (FileManager.default.isExecutableFile(atPath: url.path) ? "{file}" : nil) else {
            message = "No run command for .\(ext) files — add one in Settings → Editor."
            return
        }
        let command = template.replacingOccurrences(of: "{file}", with: ShellLauncher.shellEscape(url.path))
        ws.runInTab(tab, command: command, cwd: url.deletingLastPathComponent().path)
    }
}
