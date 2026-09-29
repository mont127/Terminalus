import AppKit
import TerminalusCore

/// One row of the file tree. Directories load their children lazily; `allChildren == nil` means
/// "not loaded yet". `visibleChildren` is `allChildren` after hidden/ignore filters and sorting.
final class FileNode: NSObject {
    enum Kind {
        case entry
        case loading
        case message(String)
        case more(Int)
    }

    let path: String
    let name: String
    let kind: Kind
    private(set) var isDirectory: Bool
    private(set) var isSymlink: Bool
    private(set) var isPackage: Bool
    private(set) var isHiddenFile: Bool
    private(set) var size: Int64?
    private(set) var modified: Date?
    weak var parent: FileNode?

    var allChildren: [FileNode]?
    var visibleChildren: [FileNode] = []
    var loadError: String?
    var isLoading = false
    /// Placeholder rows are cached so NSOutlineView sees stable item identities.
    lazy var loadingPlaceholder = FileNode(placeholder: .loading, parent: self)
    private var messageNode: FileNode?
    private var moreNode: FileNode?

    init(path: String, name: String? = nil, isDirectory: Bool, isSymlink: Bool = false, isPackage: Bool = false,
         isHidden: Bool = false, size: Int64? = nil, modified: Date? = nil) {
        self.path = path
        self.name = name ?? (path == "/" ? "/" : (path as NSString).lastPathComponent)
        self.kind = .entry
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.isPackage = isPackage
        self.isHiddenFile = isHidden
        self.size = size
        self.modified = modified
    }

    private init(placeholder: Kind, parent: FileNode) {
        self.path = parent.path + "/\u{0}placeholder"
        self.name = ""
        self.kind = placeholder
        self.isDirectory = false
        self.isSymlink = false
        self.isPackage = false
        self.isHiddenFile = false
        self.parent = parent
    }

    var isPlaceholder: Bool {
        if case .entry = kind { return false }
        return true
    }

    var isExpandable: Bool { isDirectory && !isPackage && !isPlaceholder }
    var isLoaded: Bool { allChildren != nil }
    var url: URL { URL(fileURLWithPath: path) }
    var fileExtension: String { (name as NSString).pathExtension.lowercased() }

    /// Rows the outline view shows under this node (children plus any placeholder).
    var displayChildren: [FileNode] {
        guard isExpandable else { return [] }
        if allChildren == nil { return [loadingPlaceholder] }
        var out = visibleChildren
        if let err = loadError {
            if messageNode == nil { messageNode = FileNode(placeholder: .message(err), parent: self) }
            out.append(messageNode!)
        } else if out.isEmpty {
            if messageNode == nil { messageNode = FileNode(placeholder: .message("Empty folder"), parent: self) }
            out.append(messageNode!)
        }
        return out
    }

    func setTruncated(_ count: Int) {
        moreNode = count > 0 ? FileNode(placeholder: .more(count), parent: self) : nil
        if let m = moreNode { visibleChildren.append(m) }
    }

    func resetMessage() { messageNode = nil }

    func update(from other: FileNode) {
        isDirectory = other.isDirectory
        isSymlink = other.isSymlink
        isPackage = other.isPackage
        isHiddenFile = other.isHiddenFile
        size = other.size
        modified = other.modified
    }

    // MARK: Loading (runs on a background queue; returns fresh nodes without parents)

    static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey,
    ]

    static func readChildren(of path: String) -> Result<[FileNode], Error> {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: resourceKeys, options: [])
            var nodes: [FileNode] = []
            nodes.reserveCapacity(urls.count)
            for u in urls {
                let v = try? u.resourceValues(forKeys: Set(resourceKeys))
                let name = u.lastPathComponent
                let childPath = path == "/" ? "/" + name : path + "/" + name
                let isLink = v?.isSymbolicLink ?? false
                var isDir = v?.isDirectory ?? false
                if isLink {
                    var st = stat()
                    if stat(childPath, &st) == 0 { isDir = (st.st_mode & S_IFMT) == S_IFDIR }
                }
                nodes.append(FileNode(path: childPath, name: name, isDirectory: isDir, isSymlink: isLink,
                                      isPackage: isDir && (v?.isPackage ?? false),
                                      isHidden: (v?.isHidden ?? false) || name.hasPrefix("."),
                                      size: v?.fileSize.map(Int64.init), modified: v?.contentModificationDate))
            }
            return .success(nodes)
        } catch {
            return .failure(error)
        }
    }
}
