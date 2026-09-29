import Foundation

/// Shell startup shims that make zsh and bash report their working directory (OSC 7) and command
/// lifecycle (OSC 6973: `hello;<shell>;<ver>`, `cmd;<text>`, `done;<exit>`) back to Terminalus.
/// The scripts are embedded here and written to Application Support whenever their content changes.
public enum ShellIntegration {
    public static let oscCode = 6973

    public static var directory: URL { Paths.appSupport.appendingPathComponent("shell-integration", isDirectory: true) }
    public static var zshDirectory: URL { directory.appendingPathComponent("zsh", isDirectory: true) }
    public static var bashRCFile: URL { directory.appendingPathComponent("bash/terminalus.bash") }

    /// Writes the shim files if missing or outdated. Safe to call on every launch.
    @discardableResult
    public static func install() -> Bool {
        let files: [(String, String)] = [
            ("zsh/.zshenv", zshEnv),
            ("zsh/terminalus.zsh", zshIntegration),
            ("bash/terminalus.bash", bashIntegration),
        ]
        var ok = true
        for (rel, content) in files {
            let url = directory.appendingPathComponent(rel)
            if (try? String(contentsOf: url, encoding: .utf8)) == content { continue }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                ok = false
            }
        }
        return ok
    }

    // The only startup file in the shim ZDOTDIR. It restores the user's ZDOTDIR before anything else so
    // /etc/zprofile, ~/.zprofile, /etc/zshrc (HISTFILE), ~/.zshrc and ~/.zlogin all resolve normally.
    static let zshEnv = #"""
    # Terminalus zsh bootstrap (generated; changes are overwritten).
    if [[ -n "${TERMINALUS_ORIG_ZDOTDIR+X}" ]]; then
      builtin export ZDOTDIR="$TERMINALUS_ORIG_ZDOTDIR"
      builtin unset TERMINALUS_ORIG_ZDOTDIR
    else
      builtin unset ZDOTDIR
    fi
    {
      builtin typeset _tls_f="${ZDOTDIR-$HOME}/.zshenv"
      [[ ! -r "$_tls_f" ]] || builtin source -- "$_tls_f"
    } always {
      if [[ -o interactive && -n "${TERMINALUS_INTEGRATION_DIR-}" ]]; then
        builtin typeset _tls_f="$TERMINALUS_INTEGRATION_DIR/zsh/terminalus.zsh"
        [[ ! -r "$_tls_f" ]] || builtin source -- "$_tls_f"
      fi
      builtin unset _tls_f
    }

    """#

    static let zshIntegration = #"""
    # Terminalus zsh integration (generated; changes are overwritten).
    [[ -n "${_TERMINALUS_ZSH_LOADED-}" ]] && return 0
    typeset -g _TERMINALUS_ZSH_LOADED=1
    builtin autoload -Uz add-zsh-hook

    _terminalus_urlencode() {
      emulate -L zsh
      local LC_ALL=C s=$1 out= ch hex
      local -i i
      for (( i = 1; i <= ${#s}; i++ )); do
        ch=${s[i]}
        if [[ $ch == [A-Za-z0-9/._~-] ]]; then out+=$ch
        else builtin printf -v hex '%%%02X' "'$ch"; out+=$hex; fi
      done
      REPLY=$out
    }
    _terminalus_report_cwd() {
      _terminalus_urlencode "$PWD"
      builtin printf '\e]7;file://%s%s\a' "$HOST" "$REPLY"
    }
    _terminalus_precmd() {
      local ret=$?
      if [[ -n "${_terminalus_cmd_running-}" ]]; then
        builtin printf '\e]6973;done;%s\a' "$ret"
        unset _terminalus_cmd_running
      fi
      _terminalus_report_cwd
      # The PATH after all startup files, so panel commands find the same programs.
      if [[ "$PATH" != "${_terminalus_last_path-}" ]]; then
        typeset -g _terminalus_last_path=$PATH
        _terminalus_urlencode "$PATH"
        builtin printf '\e]6973;path;%s\a' "$REPLY"
      fi
    }
    _terminalus_preexec() {
      typeset -g _terminalus_cmd_running=1
      local c=${1//[[:cntrl:]]/ }
      builtin printf '\e]6973;cmd;%s\a' "${c[1,512]}"
    }
    add-zsh-hook precmd  _terminalus_precmd
    add-zsh-hook preexec _terminalus_preexec
    add-zsh-hook chpwd   _terminalus_report_cwd

    # Editors listed in TERMINALUS_EDIT_COMMANDS open in Terminalus' built-in editor. The function asks the
    # app to open the files, then blocks on a FIFO until they are closed (like a real editor would).
    # The app answers "fallback" to run the real program instead. `command nano` always runs the real one.
    if [[ -n "${TERMINALUS_EDIT_COMMANDS-}" ]] && (( $+commands[mkfifo] )); then
      _terminalus_edit() {
        emulate -L zsh
        local cmd=$1; shift
        local fifo="${TMPDIR:-/tmp}/terminalus-edit.$$.$RANDOM"
        if ! command mkfifo -m 600 -- "$fifo" 2>/dev/null; then command $cmd "$@"; return; fi
        local out= line=0 a flags=0
        for a in "$@"; do
          if [[ $a =~ '^\+[0-9]+$' ]]; then line=${a#+}; continue; fi
          if [[ $a == [-+]* ]]; then flags=1; continue; fi
          _terminalus_urlencode "${a:A}"; out+=";${line}:${REPLY}"; line=0
        done
        # Only options (--help, -, …) and no files: that's for the real program.
        if [[ -z $out && $flags == 1 ]]; then command rm -f -- "$fifo"; command $cmd "$@"; return; fi
        _terminalus_urlencode "$fifo"
        builtin printf '\e]6973;edit;%s;%s%s\a' "$cmd" "$REPLY" "$out"
        local reply=
        { builtin read -r reply < "$fifo" } 2>/dev/null
        command rm -f -- "$fifo"
        if [[ $reply == fallback ]]; then command $cmd "$@"; return; fi
        return ${reply:-0}
      }
      for _tls_c in ${(s: :)TERMINALUS_EDIT_COMMANDS}; do
        eval "function $_tls_c { _terminalus_edit $_tls_c \"\$@\" }"
      done
      unset _tls_c
    fi
    builtin printf '\e]6973;hello;zsh;1\a'
    builtin unset TERMINALUS_INTEGRATION_DIR TERMINALUS_EDIT_COMMANDS

    """#

    // bash ignores --rcfile for login shells, so login semantics are emulated here.
    static let bashIntegration = #"""
    # Terminalus bash integration (generated; changes are overwritten).
    if [[ -n "${TERMINALUS_BASH_LOGIN-}" ]]; then
      unset TERMINALUS_BASH_LOGIN
      [[ -r /etc/profile ]] && . /etc/profile
      for __tls_f in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
        [[ -r "$__tls_f" ]] && { . "$__tls_f"; break; }
      done
      unset __tls_f
    else
      [[ -r /etc/bashrc ]] && . /etc/bashrc
      [[ -r "$HOME/.bashrc" ]] && . "$HOME/.bashrc"
    fi

    __terminalus_urlencode() {
      local LC_ALL=C s="$1" out="" c h i
      for (( i = 0; i < ${#s}; i++ )); do
        c=${s:i:1}
        case "$c" in
          [a-zA-Z0-9/._~-]) out+="$c" ;;
          *) printf -v h '%d' "'$c"; printf -v h '%%%02X' $(( h & 255 )); out+="$h" ;;
        esac
      done
      REPLY=$out
    }
    __terminalus_prompt() {
      local ret=$?
      if [[ -n "${__terminalus_cmd_running-}" ]]; then
        printf '\e]6973;done;%s\a' "$ret"
        unset __terminalus_cmd_running
      fi
      __terminalus_urlencode "$PWD"
      printf '\e]7;file://%s%s\a' "$HOSTNAME" "$REPLY"
      if [[ "$PATH" != "${__terminalus_last_path-}" ]]; then
        __terminalus_last_path=$PATH
        __terminalus_urlencode "$PATH"
        printf '\e]6973;path;%s\a' "$REPLY"
      fi
      return $ret
    }
    # Runs last in PROMPT_COMMAND, so the DEBUG trap ignores the user's own prompt commands.
    __terminalus_ready() {
      __terminalus_at_prompt=1
      __terminalus_hist=$(HISTTIMEFORMAT= builtin history 1 2>/dev/null)
    }
    __terminalus_debug() {
      [[ -n "${__terminalus_at_prompt-}" ]] || return 0
      [[ -n "${COMP_LINE-}" ]] && return 0
      case "$BASH_COMMAND" in __terminalus_*) return 0 ;; esac
      unset __terminalus_at_prompt
      __terminalus_cmd_running=1
      # The whole command line comes from history (BASH_COMMAND is only the first simple command);
      # if history did not change (HISTCONTROL=ignorespace…), fall back to BASH_COMMAND.
      local h c
      h=$(HISTTIMEFORMAT= builtin history 1 2>/dev/null)
      if [[ -n "$h" && "$h" != "${__terminalus_hist-}" ]]; then
        read -r _ c <<< "$h"
      else
        c=$BASH_COMMAND
      fi
      c="${c//[[:cntrl:]]/ }"
      printf '\e]6973;cmd;%s\a' "${c:0:512}"
    }
    trap '__terminalus_debug' DEBUG
    case ";${PROMPT_COMMAND-};" in
      *";__terminalus_prompt;"*) ;;
      *) PROMPT_COMMAND="__terminalus_prompt${PROMPT_COMMAND:+;$PROMPT_COMMAND};__terminalus_ready" ;;
    esac
    if [[ -n "${TERMINALUS_EDIT_COMMANDS-}" ]] && command -v mkfifo >/dev/null 2>&1; then
      __terminalus_edit() {
        local cmd=$1; shift
        local fifo="${TMPDIR:-/tmp}/terminalus-edit.$$.$RANDOM"
        if ! command mkfifo -m 600 "$fifo" 2>/dev/null; then command "$cmd" "$@"; return; fi
        local out="" line=0 a p flags=0
        for a in "$@"; do
          if [[ $a =~ ^\+[0-9]+$ ]]; then line=${a#+}; continue; fi
          case "$a" in -*|+*) flags=1; continue ;; /*) p="$a" ;; *) p="$PWD/$a" ;; esac
          __terminalus_urlencode "$p"; out="$out;${line}:${REPLY}"; line=0
        done
        if [[ -z $out && $flags == 1 ]]; then command rm -f "$fifo"; command "$cmd" "$@"; return; fi
        __terminalus_urlencode "$fifo"
        printf '\e]6973;edit;%s;%s%s\a' "$cmd" "$REPLY" "$out"
        local reply=""
        read -r reply < "$fifo" 2>/dev/null
        command rm -f "$fifo"
        if [[ $reply == fallback ]]; then command "$cmd" "$@"; return; fi
        return ${reply:-0}
      }
      for __tls_c in $TERMINALUS_EDIT_COMMANDS; do
        eval "$__tls_c() { __terminalus_edit $__tls_c \"\$@\"; }"
      done
      unset __tls_c
    fi
    printf '\e]6973;hello;bash;1\a'
    unset TERMINALUS_INTEGRATION_DIR TERMINALUS_EDIT_COMMANDS

    """#
}

/// Messages sent by the integration scripts through OSC 6973.
public enum IntegrationMessage: Equatable, Sendable {
    case hello(shell: String)
    case commandStarted(String)
    case commandFinished(exitCode: Int32)
    /// `nano +12 a.txt b.txt` → edit(command: "nano", fifo: …, files: [(a.txt, 12), (b.txt, 0)])
    case edit(command: String, fifo: String, files: [EditTarget])
    /// The shell's PATH after its startup files ran.
    case path(String)

    public init?(payload: String) {
        let parts = payload.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let kind = parts.first else { return nil }
        let rest = parts.count > 1 ? parts[1] : ""
        switch kind {
        case "hello":
            self = .hello(shell: String(rest.split(separator: ";").first ?? ""))
        case "cmd":
            self = .commandStarted(rest)
        case "done":
            self = .commandFinished(exitCode: Int32(rest) ?? 0)
        case "path":
            self = .path(rest.removingPercentEncoding ?? rest)
        case "edit":
            // edit;<command>;<fifo, url-encoded>;<line>:<path, url-encoded>;…
            let parts = rest.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2, let fifo = parts[1].removingPercentEncoding else { return nil }
            var files: [EditTarget] = []
            for item in parts.dropFirst(2) where !item.isEmpty {
                let pieces = item.split(separator: ":", maxSplits: 1).map(String.init)
                guard pieces.count == 2, let path = pieces[1].removingPercentEncoding else { continue }
                files.append(EditTarget(path: path, line: Int(pieces[0]) ?? 0))
            }
            self = .edit(command: parts[0], fifo: fifo, files: files)
        default:
            return nil
        }
    }
}

public struct EditTarget: Equatable, Sendable {
    public var path: String
    /// 1-based line to jump to; 0 = start.
    public var line: Int

    public init(path: String, line: Int = 0) {
        self.path = path
        self.line = line
    }
}

/// Answers a waiting editor function. Only writes to a FIFO owned by us, so a program printing a
/// spoofed escape sequence can't make Terminalus write into an arbitrary file.
public enum EditReply {
    public static func isSafeFIFO(_ path: String) -> Bool {
        guard (path as NSString).lastPathComponent.hasPrefix("terminalus-edit.") else { return false }
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        return (st.st_mode & S_IFMT) == S_IFIFO && st.st_uid == getuid()
    }

    /// `text` is an exit status ("0") or "fallback" (run the real editor).
    public static func send(_ text: String, to fifo: String) {
        guard isSafeFIFO(fifo) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            // Non-blocking: if nobody is reading anymore (Ctrl-C), open fails with ENXIO and we give up.
            let fd = open(fifo, O_WRONLY | O_NONBLOCK)
            guard fd >= 0 else { return }
            let line = text + "\n"
            _ = line.withCString { write(fd, $0, strlen($0)) }
            close(fd)
        }
    }
}
