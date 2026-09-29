import Foundation

public enum GitFileState: String, Sendable, Codable {
    case modified, added, deleted, renamed, untracked, conflicted, ignored

    /// Priority when aggregating onto parent directories (higher wins).
    public var priority: Int {
        switch self {
        case .conflicted: 6
        case .modified: 5
        case .deleted: 4
        case .renamed: 3
        case .added: 2
        case .untracked: 1
        case .ignored: 0
        }
    }

    public var letter: String {
        switch self {
        case .modified: "M"
        case .added: "A"
        case .deleted: "D"
        case .renamed: "R"
        case .untracked: "U"
        case .conflicted: "!"
        case .ignored: "I"
        }
    }
}

public struct GitStatus: Equatable, Sendable {
    public var root: String
    public var branch: String?
    public var upstream: String?
    public var ahead: Int = 0
    public var behind: Int = 0
    public var detached: Bool = false
    /// Absolute path → state, for changed files only.
    public var files: [String: GitFileState] = [:]
    /// Absolute directory path → strongest state among its descendants.
    public var directories: [String: GitFileState] = [:]
    public var stagedCount: Int = 0
    public var unstagedCount: Int = 0
    public var untrackedCount: Int = 0
    public var conflictCount: Int = 0

    public var isDirty: Bool { !files.isEmpty }

    public func state(for path: String) -> GitFileState? {
        files[path] ?? directories[path]
    }
}

public enum GitStatusParser {
    /// Parses `git status --porcelain=v2 --branch -z` output.
    public static func parse(_ data: Data, root: String) -> GitStatus {
        var st = GitStatus(root: root)
        let records = data.split(separator: 0, omittingEmptySubsequences: false)
        var i = 0
        func add(_ rel: String, _ state: GitFileState) {
            let abs = (root as NSString).appendingPathComponent(rel.hasSuffix("/") ? String(rel.dropLast()) : rel)
            st.files[abs] = state
            var dir = (abs as NSString).deletingLastPathComponent
            while dir.count >= root.count && dir != "/" {
                if let existing = st.directories[dir], existing.priority >= state.priority { break }
                st.directories[dir] = state
                if dir == root { break }
                dir = (dir as NSString).deletingLastPathComponent
            }
        }
        while i < records.count {
            let line = String(decoding: records[i], as: UTF8.self)
            i += 1
            guard let first = line.first else { continue }
            switch first {
            case "#":
                let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
                guard parts.count >= 3 else { continue }
                switch parts[1] {
                case "branch.head":
                    if parts[2] == "(detached)" {
                        st.detached = true
                    } else {
                        st.branch = parts[2]
                    }
                case "branch.upstream":
                    st.upstream = parts[2]
                case "branch.ab":
                    for tok in parts[2].split(separator: " ") {
                        if tok.hasPrefix("+") { st.ahead = Int(tok.dropFirst()) ?? 0 }
                        if tok.hasPrefix("-") { st.behind = Int(tok.dropFirst()) ?? 0 }
                    }
                case "branch.oid":
                    if st.detached || st.branch == nil { st.branch = String(parts[2].prefix(8)) }
                default:
                    break
                }
            case "1", "2":
                // 1 XY sub mH mI mW hH hI path
                // 2 XY sub mH mI mW hH hI Xscore path  (followed by a NUL-separated origPath record)
                let fieldCount = first == "1" ? 9 : 10
                let parts = line.split(separator: " ", maxSplits: fieldCount - 1, omittingEmptySubsequences: false).map(String.init)
                guard parts.count == fieldCount else { continue }
                let xy = Array(parts[1])
                let x = xy.first ?? ".", y = xy.count > 1 ? xy[1] : "."
                if x != "." { st.stagedCount += 1 }
                if y != "." { st.unstagedCount += 1 }
                let state: GitFileState
                if first == "2" {
                    state = .renamed
                } else if x == "D" || y == "D" {
                    state = .deleted
                } else if x == "A" && y == "." {
                    state = .added
                } else {
                    state = (x == "A") ? .added : .modified
                }
                add(parts[fieldCount - 1], state)
                if first == "2" { i += 1 }
            case "u":
                // u XY sub m1 m2 m3 mW h1 h2 h3 path
                let parts = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 11 else { continue }
                st.conflictCount += 1
                add(parts[10], .conflicted)
            case "?":
                st.untrackedCount += 1
                add(String(line.dropFirst(2)), .untracked)
            case "!":
                add(String(line.dropFirst(2)), .ignored)
            default:
                break
            }
        }
        return st
    }
}

/// Runs git off the main thread with a timeout; never takes the index lock.
public final class GitService: @unchecked Sendable {
    public static let shared = GitService()
    private let queue = DispatchQueue(label: "terminalus.git", qos: .utility)
    public private(set) lazy var gitPath: String? = {
        for p in ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"] where FileManager.default.isExecutableFile(atPath: p) {
            // /usr/bin/git is a shim that fails without the CLT; it is present here, so accept it.
            return p
        }
        return nil
    }()
    private var rootCache: [String: (root: String?, at: Date)] = [:]

    /// Finds the repository root containing `path` (cached for 10 s). Cheap: walks up looking for .git.
    public func repositoryRoot(for path: String) -> String? {
        var dir = (path as NSString).standardizingPath
        let fm = FileManager.default
        var hops = 0
        while hops < 64 {
            let dotgit = (dir as NSString).appendingPathComponent(".git")
            if fm.fileExists(atPath: dotgit) { return dir }
            if dir == "/" || dir.isEmpty { return nil }
            dir = (dir as NSString).deletingLastPathComponent
            hops += 1
        }
        return nil
    }

    /// Computes status for the repository containing `path`. Completion runs on the main queue.
    public func status(for path: String, timeout: TimeInterval = 5, completion: @escaping @Sendable (GitStatus?) -> Void) {
        queue.async { [self] in
            guard let root = repositoryRoot(for: path), let git = gitPath else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let out = run(git, ["-C", root, "status", "--porcelain=v2", "--branch", "-z", "-unormal"], timeout: timeout)
            let result = out.map { GitStatusParser.parse($0, root: root) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func run(_ exe: String, _ args: [String], timeout: TimeInterval) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["LC_ALL"] = "C"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let timer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        timer.cancel()
        return p.terminationStatus == 0 ? data : nil
    }
}
