import Foundation
import Darwin

/// Everything needed to start a shell inside a pseudo-terminal.
public struct ShellLaunchSpec: Equatable, Sendable {
    public var executable: String
    public var args: [String]
    /// argv[0]; a leading "-" makes the shell a login shell.
    public var execName: String
    public var environment: [String]
    public var currentDirectory: String
    public var usesIntegration: Bool
}

public enum ShellKind: String, Sendable {
    case zsh, bash, fish, other

    public init(path: String) {
        switch (path as NSString).lastPathComponent {
        case "zsh": self = .zsh
        case "bash": self = .bash
        case "fish": self = .fish
        default: self = .other
        }
    }
}

public enum ShellLauncher {
    /// The user's login shell from the password database, falling back to $SHELL and then /bin/zsh.
    public static var userShell: String {
        if let pw = getpwuid(getuid()), let sh = pw.pointee.pw_shell {
            let s = String(cString: sh)
            if !s.isEmpty, FileManager.default.isExecutableFile(atPath: s) { return s }
        }
        if let s = ProcessInfo.processInfo.environment["SHELL"], FileManager.default.isExecutableFile(atPath: s) { return s }
        return "/bin/zsh"
    }

    public static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    public static func makeSpec(profile: Profile, terminal: TerminalSettings, sessionID: String,
                                workingDirectory: String, editCommands: [String] = []) -> ShellLaunchSpec {
        let shell = profile.shellPath.isEmpty ? userShell : (profile.shellPath as NSString).expandingTildeInPath
        let kind = ShellKind(path: shell)
        let base = (shell as NSString).lastPathComponent
        let integration = terminal.shellIntegration && (kind == .zsh || kind == .bash)
        if integration { ShellIntegration.install() }

        var env = ProcessInfo.processInfo.environment
        // Variables that only make sense for the parent process.
        for key in ["TERM_SESSION_ID", "ITERM_SESSION_ID", "TERMINALUS_ORIG_ZDOTDIR", "__CFBundleIdentifier",
                    "XPC_SERVICE_NAME", "XPC_FLAGS", "OLDPWD", "PWD", "SHLVL", "_"] {
            env.removeValue(forKey: key)
        }
        env["TERM"] = terminal.termName.isEmpty ? "xterm-256color" : terminal.termName
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Terminalus"
        env["TERM_PROGRAM_VERSION"] = appVersion
        env["TERMINALUS_SESSION_ID"] = sessionID
        env["SHELL"] = shell
        if env["LANG"] == nil { env["LANG"] = defaultLang }
        if env["HOME"] == nil { env["HOME"] = NSHomeDirectory() }
        if env["USER"] == nil { env["USER"] = NSUserName() }
        if env["LOGNAME"] == nil { env["LOGNAME"] = NSUserName() }
        if env["PATH"] == nil { env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" }

        var args = profile.args
        var execName = profile.login ? "-" + base : base

        if integration {
            env["TERMINALUS_INTEGRATION_DIR"] = ShellIntegration.directory.path
            let cmds = editCommands.filter { $0.range(of: "^[A-Za-z0-9._+-]+$", options: .regularExpression) != nil }
            if !cmds.isEmpty { env["TERMINALUS_EDIT_COMMANDS"] = cmds.joined(separator: " ") }
            switch kind {
            case .zsh:
                if let orig = ProcessInfo.processInfo.environment["ZDOTDIR"] {
                    env["TERMINALUS_ORIG_ZDOTDIR"] = orig
                }
                env["ZDOTDIR"] = ShellIntegration.zshDirectory.path
            case .bash:
                // bash ignores --rcfile in login mode; the rcfile emulates login when asked to.
                if profile.login { env["TERMINALUS_BASH_LOGIN"] = "1" }
                execName = base
                args = ["--rcfile", ShellIntegration.bashRCFile.path, "-i"] + args
            default:
                break
            }
        }

        // macOS's bash prints a "default shell is now zsh" banner on every start.
        if kind == .bash && env["BASH_SILENCE_DEPRECATION_WARNING"] == nil { env["BASH_SILENCE_DEPRECATION_WARNING"] = "1" }

        for (k, v) in profile.environment { env[k] = v }

        return ShellLaunchSpec(
            executable: shell,
            args: args,
            execName: execName,
            environment: env.map { "\($0.key)=\($0.value)" }.sorted(),
            currentDirectory: workingDirectory,
            usesIntegration: integration
        )
    }

    private static var defaultLang: String {
        let id = Locale.current.identifier
        if id.contains("_") { return id.split(separator: "@").first.map(String.init).map { $0 + ".UTF-8" } ?? "en_US.UTF-8" }
        return "en_US.UTF-8"
    }

    /// Escapes a path for pasting into a POSIX shell.
    public static func shellEscape(_ s: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./~+,:@%")
        if !s.isEmpty, s.unicodeScalars.allSatisfy({ safe.contains($0) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
