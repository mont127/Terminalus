import AppKit
import Observation
import TerminalusCore

/// Custom panels created with "Import Window Code", one JSON file each.
@MainActor
@Observable
final class PanelStore {
    private(set) var panels: [CustomPanel] = []

    static var directory: URL { Paths.appSupport.appendingPathComponent("panels", isDirectory: true) }

    init() {
        reload()
    }

    func panel(id: String) -> CustomPanel? { panels.first { $0.id == id } }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        panels = files.filter { $0.pathExtension == "json" }
            .compactMap { try? dec.decode(CustomPanel.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func save(_ p: CustomPanel) {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(p) {
            try? data.write(to: Self.directory.appendingPathComponent(p.id + ".json"), options: .atomic)
        }
        if let i = panels.firstIndex(where: { $0.id == p.id }) { panels[i] = p } else { panels.append(p) }
    }

    func delete(id: String) {
        try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(id + ".json"))
        panels.removeAll { $0.id == id }
    }
}

/// Status shown in a custom panel's header.
@MainActor
@Observable
final class PanelStatus {
    var error: String?
    var running = false
    var lastRun: Date?
    var lastExit: Int32?
    var detail: String?
}

/// Runs a shell command the way the user's shell would (their PATH, the focused directory).
enum PanelCommandRunner {
    struct Result: Sendable {
        var stdout: String
        var stderr: String
        var code: Int32
        var timedOut: Bool
    }

    static func run(_ command: String, cwd: String, path: String?, columns: Int = 100, timeout: TimeInterval = 20,
                    completion: @escaping @Sendable (Result) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-f", "-c", command]
            var env = ProcessInfo.processInfo.environment
            if let path, !path.isEmpty { env["PATH"] = path }
            env["TERM"] = "xterm-256color"
            env["COLORTERM"] = "truecolor"
            env["CLICOLOR"] = "1"
            env["CLICOLOR_FORCE"] = "1"
            env["FORCE_COLOR"] = "1"
            env["COLUMNS"] = "\(columns)"
            env["PAGER"] = "cat"
            env["GIT_PAGER"] = "cat"
            env["TERM_PROGRAM"] = "Terminalus"
            p.environment = env
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: cwd, isDirectory: &isDir), isDir.boolValue {
                p.currentDirectoryURL = URL(fileURLWithPath: cwd)
            }
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch {
                completion(Result(stdout: "", stderr: error.localizedDescription, code: -1, timedOut: false))
                return
            }
            let timedOut = ProtectedFlag()
            let killer = DispatchWorkItem {
                if p.isRunning {
                    timedOut.set()
                    p.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
            // Read both pipes concurrently so neither can fill up and block the child.
            var errData = Data()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                errData = err.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            group.wait()
            p.waitUntilExit()
            killer.cancel()
            let cap = 400_000
            completion(Result(stdout: String(decoding: outData.prefix(cap), as: UTF8.self),
                              stderr: String(decoding: errData.prefix(cap), as: UTF8.self),
                              code: p.terminationStatus, timedOut: timedOut.value))
        }
    }
}

final class ProtectedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
