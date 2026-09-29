import AppKit
import Observation
import TerminalusCore

/// State and logic of one window's file tree: the root, lazy loading, following the terminal's
/// working directory, file-system watching and git status.
@MainActor
@Observable
final class FileTreeModel {
    private(set) var rootPath = "/"
    private(set) var cwd = NSHomeDirectory()
    private(set) var isRemote = false
    private(set) var gitStatus: GitStatus?

    @ObservationIgnored weak var workspace: Workspace?
    @ObservationIgnored let controller = FileTreeController()
    @ObservationIgnored private(set) var root: FileNode
    @ObservationIgnored private(set) var settings: TreeSettings
    @ObservationIgnored private var glob: GlobMatcher
    @ObservationIgnored private var loadedDirs: [String: FileNode] = [:]
    /// Folders opened automatically to reveal the cwd (collapsed again when the cwd moves on).
    @ObservationIgnored private var autoExpanded: Set<String> = []
    @ObservationIgnored private(set) var expandedPaths: Set<String> = []
    /// Keyed by node identity: after the root is replaced, a late load of an old node must not run the
    /// callbacks waiting on the new node with the same path.
    @ObservationIgnored private var pendingLoads: [ObjectIdentifier: [() -> Void]] = [:]
    @ObservationIgnored private var revealToken = 0
    @ObservationIgnored private var hasFollowed = false
    @ObservationIgnored private let loadQueue = DispatchQueue(label: "terminalus.tree.load", qos: .userInitiated, attributes: .concurrent)
    @ObservationIgnored private let gitDebouncer = Debouncer(delay: 0.5)
    @ObservationIgnored private let watchDebouncer = Debouncer(delay: 0.3)
    @ObservationIgnored private var extraLimit: [String: Int] = [:]
    @ObservationIgnored private lazy var watcher = FSEventsWatcher(debounce: 0.25) { [weak self] dirs in
        DispatchQueue.main.async { self?.filesChanged(dirs) }
    }

    init() {
        settings = AppState.shared.settings.tree
        glob = GlobMatcher(settings.ignore)
        root = FileNode(path: "/", isDirectory: true)
        controller.model = self
    }

    func stop() {
        watcher.stop()
        gitDebouncer.cancel()
    }

    // MARK: Root

    private func computeRootPath() -> String {
        switch settings.rootMode {
        case .filesystemRoot: return "/"
        case .currentDirectory: return cwd
        case .home: return NSHomeDirectory()
        case .gitRoot: return GitService.shared.repositoryRoot(for: cwd) ?? cwd
        }
    }

    private func setRoot(_ path: String) {
        rootPath = path
        root = FileNode(path: path, isDirectory: true)
        loadedDirs.removeAll()
        autoExpanded.removeAll()
        expandedPaths.removeAll()
        pendingLoads.removeAll()
        controller.reloadAll()
        controller.expand(root)
        if settings.followCwd || settings.rootMode == .currentDirectory { reveal(cwd, select: true) }
        updateWatch()
    }

    // MARK: Following the terminal

    func follow(cwd newCwd: String, remote: Bool) {
        isRemote = remote
        guard !remote else { return }
        let oldCwd = cwd
        let changed = newCwd != oldCwd || !hasFollowed
        cwd = newCwd
        let desired = computeRootPath()
        if desired != rootPath || !hasFollowed {
            hasFollowed = true
            setRoot(desired)
            scheduleGitRefresh()
            return
        }
        guard changed else { return }
        // Hidden ancestors (/usr, /private…) are forced visible while they lead to the cwd.
        let affected = Set(Paths.ancestry(of: oldCwd)).union(Paths.ancestry(of: newCwd))
        for p in affected {
            if let n = loadedDirs[p] {
                computeVisible(n)
                controller.reloadChildren(of: n)
            }
        }
        if settings.followCwd {
            if settings.collapseOnFollow { collapseStale(keeping: newCwd) }
            reveal(newCwd, select: true)
        } else {
            controller.refreshVisibleRows()
        }
        scheduleGitRefresh()
    }

    private func collapseStale(keeping path: String) {
        let keep = Set(Paths.ancestry(of: path))
        let stale = autoExpanded.filter { !keep.contains($0) }.sorted { $0.count > $1.count }
        for p in stale {
            autoExpanded.remove(p)
            if let n = loadedDirs[p] { controller.collapse(n) }
        }
    }

    /// Expands the chain of folders down to `path`, then selects and scrolls to it.
    func reveal(_ path: String, select: Bool, force: Bool = false) {
        guard Paths.isAncestor(rootPath, of: path) else { return }
        revealToken += 1
        let token = revealToken
        let chain = Paths.ancestry(of: path).filter { Paths.isAncestor(rootPath, of: $0) }
        guard chain.first == rootPath || rootPath == "/" else { return }
        step(root, chain: chain, index: 1, token: token, select: select)
    }

    private func step(_ node: FileNode, chain: [String], index: Int, token: Int, select: Bool) {
        guard token == revealToken else { return }
        if !controller.isExpanded(node) {
            if node !== root && !expandedPaths.contains(node.path) { autoExpanded.insert(node.path) }
            controller.expand(node)
        }
        load(node) { [weak self] in
            guard let self, token == self.revealToken else { return }
            guard index < chain.count, let child = node.allChildren?.first(where: { $0.path == chain[index] }) else {
                self.controller.scrollTo(node, select: select)
                return
            }
            if !child.isExpandable {
                self.controller.scrollTo(child, select: select)
                return
            }
            if index == chain.count - 1 {
                // The target folder itself opens too, so its contents are visible.
                if !self.controller.isExpanded(child) {
                    if !self.expandedPaths.contains(child.path) { self.autoExpanded.insert(child.path) }
                    self.controller.expand(child)
                }
                self.load(child) { [weak self] in
                    guard let self, token == self.revealToken else { return }
                    self.controller.scrollTo(child, select: select)
                }
                return
            }
            self.step(child, chain: chain, index: index + 1, token: token, select: select)
        }
    }

    // MARK: Loading

    func load(_ node: FileNode, completion: (() -> Void)? = nil) {
        guard node.isExpandable else { completion?(); return }
        if node.isLoaded {
            completion?()
            return
        }
        let key = ObjectIdentifier(node)
        if pendingLoads[key] != nil {
            if let c = completion { pendingLoads[key]?.append(c) }
            return
        }
        pendingLoads[key] = completion.map { [$0] } ?? []
        node.isLoading = true
        let path = node.path
        loadQueue.async {
            let result = FileNode.readChildren(of: path)
            DispatchQueue.main.async { [weak self] in self?.finishLoad(node, result) }
        }
    }

    private func finishLoad(_ node: FileNode, _ result: Result<[FileNode], Error>) {
        node.isLoading = false
        let callbacks = pendingLoads.removeValue(forKey: ObjectIdentifier(node)) ?? []
        // Ignore loads for nodes of a tree that has since been replaced.
        var top = node
        while let p = top.parent { top = p }
        guard top === root else { return }
        apply(result, to: node)
        loadedDirs[node.path] = node
        computeVisible(node)
        controller.reloadChildren(of: node)
        callbacks.forEach { $0() }
        scheduleWatchUpdate()
    }

    private func apply(_ result: Result<[FileNode], Error>, to node: FileNode) {
        switch result {
        case .success(let fresh):
            node.loadError = nil
            var existing: [String: FileNode] = [:]
            for c in node.allChildren ?? [] { existing[c.name] = c }
            var out: [FileNode] = []
            out.reserveCapacity(fresh.count)
            for f in fresh {
                if let e = existing.removeValue(forKey: f.name) {
                    e.update(from: f)
                    out.append(e)
                } else {
                    f.parent = node
                    out.append(f)
                }
            }
            for gone in existing.values { forget(gone) }
            node.allChildren = out
        case .failure(let error):
            node.allChildren = []
            let ns = error as NSError
            if ns.code == NSFileReadNoPermissionError || (ns.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == Int(EPERM) || (ns.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == Int(EACCES) {
                node.loadError = "Permission denied"
            } else {
                node.loadError = "Can't read folder"
            }
        }
        node.resetMessage()
    }

    private func forget(_ node: FileNode) {
        loadedDirs[node.path] = nil
        autoExpanded.remove(node.path)
        for c in node.allChildren ?? [] { forget(c) }
    }

    /// Shows more children of a folder whose listing was truncated.
    func showMore(in node: FileNode) {
        extraLimit[node.path, default: 0] += settings.maxChildren
        computeVisible(node)
        controller.reloadChildren(of: node)
    }

    // MARK: Filtering & sorting

    private func computeVisible(_ node: FileNode) {
        guard let all = node.allChildren else { return }
        let forced = Set(Paths.ancestry(of: cwd))
        var list = all.filter { c in
            if forced.contains(c.path) { return true }
            if !settings.showHidden && c.isHiddenFile { return false }
            if glob.matches(c.name) { return false }
            return true
        }
        sort(&list)
        let limit = settings.maxChildren + extraLimit[node.path, default: 0]
        var truncated = 0
        if list.count > limit {
            let kept = Array(list.prefix(limit))
            let forcedExtra = list.dropFirst(limit).filter { forced.contains($0.path) }
            truncated = list.count - limit - forcedExtra.count
            list = kept + forcedExtra
        }
        node.visibleChildren = list
        node.resetMessage()
        node.setTruncated(truncated)
    }

    private func sort(_ list: inout [FileNode]) {
        let s = settings
        list.sort { a, b in
            if s.foldersFirst && a.isExpandable != b.isExpandable { return a.isExpandable }
            let ordered: Bool
            switch s.sortBy {
            case .name:
                ordered = a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .modified:
                let da = a.modified ?? .distantPast, db = b.modified ?? .distantPast
                ordered = da == db ? a.name.localizedStandardCompare(b.name) == .orderedAscending : da > db
            case .size:
                let sa = a.size ?? -1, sb = b.size ?? -1
                ordered = sa == sb ? a.name.localizedStandardCompare(b.name) == .orderedAscending : sa > sb
            case .kind:
                let ea = a.fileExtension, eb = b.fileExtension
                ordered = ea == eb ? a.name.localizedStandardCompare(b.name) == .orderedAscending : ea < eb
            }
            return s.sortAscending ? ordered : !ordered
        }
    }

    // MARK: Settings

    func apply(settings new: TreeSettings) {
        let old = settings
        settings = new
        glob = GlobMatcher(new.ignore)
        if old.rootMode != new.rootMode {
            setRoot(computeRootPath())
            return
        }
        if old.showHidden != new.showHidden || old.ignore != new.ignore || old.foldersFirst != new.foldersFirst
            || old.sortBy != new.sortBy || old.sortAscending != new.sortAscending || old.maxChildren != new.maxChildren {
            for n in loadedDirs.values { computeVisible(n) }
        }
        controller.applyStyle()
        controller.reloadAll()
        if new.followCwd && !old.followCwd { reveal(cwd, select: true) }
    }

    // MARK: Expansion bookkeeping (called by the controller)

    func didExpand(_ node: FileNode, byUser: Bool) {
        expandedPaths.insert(node.path)
        if byUser { autoExpanded.remove(node.path) }
        load(node)
        scheduleWatchUpdate()
    }

    func didCollapse(_ node: FileNode) {
        expandedPaths.remove(node.path)
        autoExpanded.remove(node.path)
        scheduleWatchUpdate()
    }

    func collapseAll() {
        for p in expandedPaths.sorted(by: { $0.count > $1.count }) where p != rootPath {
            if let n = loadedDirs[p] { controller.collapse(n) }
        }
        autoExpanded.removeAll()
    }

    func node(at path: String) -> FileNode? { loadedDirs[path] }

    // MARK: Watching

    private func scheduleWatchUpdate() {
        watchDebouncer.call { [weak self] in
            Task { @MainActor in self?.updateWatch() }
        }
    }

    private func updateWatch() {
        let paths = expandedPaths.filter { loadedDirs[$0] != nil }
        watcher.watch(paths.isEmpty ? [rootPath] : Array(paths))
    }

    private func filesChanged(_ dirs: Set<String>) {
        var touchedRepo = false
        let repo = gitStatus?.root
        for d in dirs {
            if let r = repo, Paths.isAncestor(r, of: d), !d.contains("/.git/"), !d.hasSuffix("/.git") { touchedRepo = true }
            guard let node = loadedDirs[d] else { continue }
            let path = node.path
            loadQueue.async {
                let result = FileNode.readChildren(of: path)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.loadedDirs[path] === node else { return }
                    self.apply(result, to: node)
                    self.computeVisible(node)
                    self.controller.reloadChildren(of: node)
                }
            }
        }
        if touchedRepo || dirs.contains(where: { $0.hasSuffix("/.git") || $0.contains("/.git/") && $0.hasSuffix("/refs/heads") }) {
            scheduleGitRefresh()
        }
    }

    // MARK: Git

    func scheduleGitRefresh() {
        let path = cwd
        gitDebouncer.call { [weak self] in
            GitService.shared.status(for: path) { status in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.gitStatus != status {
                        self.gitStatus = status
                        self.controller.refreshVisibleRows()
                        self.workspace?.panelsGitChanged()
                    }
                }
            }
        }
    }

    // MARK: Focus

    func focusOutline() {
        controller.focusOutline()
    }
}
