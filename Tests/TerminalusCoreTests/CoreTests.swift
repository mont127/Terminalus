import Foundation
import Testing
@testable import TerminalusCore

@Suite struct FuzzyTests {
    @Test func matchesSubsequence() {
        #expect(FuzzyMatcher.score("theme syn", in: "Theme: Synthwave '84 Appearance") != nil)
        #expect(FuzzyMatcher.score("theme syn", in: "New Window Shell") == nil)
        let ranked = FuzzyMatcher.rank(["New Window", "Theme: Synthwave '84", "Theme: Nord"], query: "theme syn") { $0 }
        #expect(ranked == ["Theme: Synthwave '84"])
    }

    @Test func prefersWordStarts() {
        let a = FuzzyMatcher.score("sr", in: "Split Right")!
        let b = FuzzyMatcher.score("sr", in: "Ssssssr")!
        #expect(a > b)
    }
}

@Suite struct SettingsTests {
    @Test func mergeFillsMissingKeys() throws {
        let json = #"{"terminal": {"font": {"size": 17}}, "tree": {"showHidden": true}}"#
        let s = try JSONMerge.decodeMerged(AppSettings.self, from: Data(json.utf8), defaults: AppSettings())
        #expect(s.terminal.font.size == 17)
        #expect(s.terminal.scrollback == TerminalSettings().scrollback)
        #expect(s.tree.showHidden)
        #expect(s.appearance.themeID == "graphite")
    }

    @Test func shortArrayEntriesDecode() throws {
        let json = #"{"stats": {"widgets": [{"kind": "cpu"}, {"kind": "memory", "style": "bar"}]}, "profiles": [{"id": "x"}]}"#
        let s = try JSONMerge.decodeMerged(AppSettings.self, from: Data(json.utf8), defaults: AppSettings())
        #expect(s.stats.widgets.count == 2)
        #expect(s.stats.widgets[1].style == .bar)
        #expect(s.profiles[0].name == "x")
        #expect(s.stats.normalizedWidgets.count == WidgetKind.allCases.count)
    }

    @Test func badValueIsReported() {
        let json = #"{"terminal": {"cursor": {"shape": "triangle"}}}"#
        #expect(throws: SettingsCodingError.self) {
            _ = try JSONMerge.decodeMerged(AppSettings.self, from: Data(json.utf8), defaults: AppSettings())
        }
    }

    @Test func roundTrip() throws {
        var s = AppSettings()
        s.layout.move(PanelID.system, to: .right)
        s.keybindings["newTab"] = "cmd+shift+n"
        let data = try JSONMerge.prettyEncode(s)
        let back = try JSONMerge.decodeMerged(AppSettings.self, from: data, defaults: AppSettings())
        #expect(back == s)
    }
}

@Suite struct OSC7Tests {
    @Test func parsesFileURL() {
        let loc = OSC7Location("file://localhost/tmp/a%20b/%C5%99")!
        #expect(loc.path == "/tmp/a b/ř")
        #expect(loc.isLocal)
    }

    @Test func remoteHost() {
        let loc = OSC7Location("file://some-server.example.com/home/me")!
        #expect(!loc.isLocal)
        #expect(loc.host == "some-server.example.com")
    }

    @Test func integrationMessages() {
        #expect(IntegrationMessage(payload: "hello;zsh;1") == .hello(shell: "zsh"))
        #expect(IntegrationMessage(payload: "cmd;ls -la; echo hi") == .commandStarted("ls -la; echo hi"))
        #expect(IntegrationMessage(payload: "done;130") == .commandFinished(exitCode: 130))
    }
}

@Suite struct GitTests {
    @Test func parsesPorcelainV2() {
        var out = "# branch.oid abcdef1234567890\u{0}# branch.head main\u{0}# branch.upstream origin/main\u{0}# branch.ab +2 -1\u{0}"
        out += "1 .M N... 100644 100644 100644 aaa bbb src/a.swift\u{0}"
        out += "1 A. N... 000000 100644 100644 000 ccc src/new.swift\u{0}"
        out += "2 R. N... 100644 100644 100644 ddd eee R100 docs/new.md\u{0}docs/old.md\u{0}"
        out += "? notes.txt\u{0}"
        let st = GitStatusParser.parse(Data(out.utf8), root: "/repo")
        #expect(st.branch == "main")
        #expect(st.ahead == 2 && st.behind == 1)
        #expect(st.files["/repo/src/a.swift"] == .modified)
        #expect(st.files["/repo/src/new.swift"] == .added)
        #expect(st.files["/repo/docs/new.md"] == .renamed)
        #expect(st.files["/repo/notes.txt"] == .untracked)
        #expect(st.directories["/repo/src"] == .modified)
        #expect(st.untrackedCount == 1)
    }
}

@Suite struct InputTests {
    @Test func keyCombos() {
        let c = KeyCombo("cmd+shift+t")!
        #expect(c.command && c.shift && !c.option && c.key == "t")
        #expect(c.description == "shift+cmd+t")
        #expect(KeyCombo("cmd++")?.key == "+")
        #expect(KeyCombo("ctrl+alt+left")?.symbolic == "⌃⌥←")
        #expect(KeyCombo("cmd+nonsense") == nil)
        #expect(KeyCombo("hyper+x") == nil)
    }

    @Test func defaultBindingsAreUnique() {
        let b = AppAction.resolvedBindings(overrides: [:])
        let combos = Array(b.values)
        #expect(Set(combos).count == combos.count)
    }
}

@Suite struct PaneTests {
    @Test func splitAndRemove() {
        var t = PaneNode.leaf("a")
        t = t.splitting("a", with: "b", axis: .horizontal)
        t = t.splitting("b", with: "c", axis: .vertical)
        #expect(t.leaves == ["a", "b", "c"])
        #expect(t.neighbor(of: "a", .right) != nil)
        #expect(t.neighbor(of: "b", .down) == "c")
        #expect(t.neighbor(of: "c", .up) == "b")
        #expect(t.removing("b")?.leaves == ["a", "c"])
        #expect(PaneNode.leaf("a").removing("a") == nil)
    }
}

@Suite struct MiscTests {
    @Test func ringBuffer() {
        var r = RingBuffer<Int>(capacity: 3)
        for i in 1...5 { r.append(i) }
        #expect(r.elements == [3, 4, 5])
        #expect(r.last == 5)
        r.resize(2)
        #expect(r.elements == [4, 5])
    }

    @Test func globs() {
        let g = GlobMatcher(["*.o", "node_modules", ".DS_Store"])
        #expect(g.matches("main.o"))
        #expect(g.matches("node_modules"))
        #expect(!g.matches("main.c"))
    }

    @Test func shellEscape() {
        #expect(ShellLauncher.shellEscape("/tmp/plain") == "/tmp/plain")
        #expect(ShellLauncher.shellEscape("/tmp/a b") == "'/tmp/a b'")
        #expect(ShellLauncher.shellEscape("it's") == "'it'\\''s'")
    }

    @Test func themesAreValid() {
        #expect(Theme.builtins.count == 30)
        #expect(Set(Theme.builtins.map(\.id)).count == Theme.builtins.count)
        for t in Theme.builtins {
            #expect(t.ansi.count == 16, "\(t.id)")
            #expect(RGBA(hex: t.background) != nil, "\(t.id)")
        }
    }

    @Test func iTermRoundTrip() throws {
        let t = Theme.builtin(id: "dracula")!
        let data = try ITermColors.export(t)
        let back = try ITermColors.importTheme(data: data, name: "Dracula Copy")
        #expect(back.ansi == t.ansi)
        #expect(back.background == t.background)
    }

    @Test func ancestry() {
        #expect(Paths.ancestry(of: "/usr/local/bin") == ["/", "/usr", "/usr/local", "/usr/local/bin"])
        #expect(Paths.isAncestor("/usr", of: "/usr/local"))
        #expect(!Paths.isAncestor("/us", of: "/usr"))
    }
}

@Suite struct EditorIntegrationTests {
    @Test func parsesEditRequest() {
        let msg = IntegrationMessage(payload: "edit;nano;%2Ftmp%2Fterminalus-edit.1.2;12:%2Ftmp%2Fa%20b.txt;0:%2Ftmp%2Fc.py")
        #expect(msg == .edit(command: "nano", fifo: "/tmp/terminalus-edit.1.2",
                             files: [EditTarget(path: "/tmp/a b.txt", line: 12), EditTarget(path: "/tmp/c.py", line: 0)]))
        #expect(IntegrationMessage(payload: "edit;vim;%2Ftmp%2Fx") == .edit(command: "vim", fifo: "/tmp/x", files: []))
    }

    @Test func refusesNonFIFOReplies() {
        let path = NSTemporaryDirectory() + "terminalus-edit.not-a-fifo"
        FileManager.default.createFile(atPath: path, contents: Data("keep".utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(!EditReply.isSafeFIFO(path))
        #expect(!EditReply.isSafeFIFO("/etc/hosts"))
        let fifo = NSTemporaryDirectory() + "terminalus-edit.test\(getpid())"
        #expect(mkfifo(fifo, 0o600) == 0)
        defer { unlink(fifo) }
        #expect(EditReply.isSafeFIFO(fifo))
    }
}

@Suite struct PanelCodeTests {
    @Test func fencedHTML() {
        let p = PanelCodeParser.parse("```html\n<title>Pomodoro</title>\n<div id=t></div><script>let x = 1;</script>\n```")
        #expect(p.kind == .web)
        #expect(p.name == "Pomodoro")
        #expect(!p.code.contains("```"))
    }

    @Test func manifestCommand() {
        let p = PanelCodeParser.parse(#"{"name": "Git log", "command": "git log --oneline -10", "side": "right", "refresh": 10}"#)
        #expect(p.kind == .command)
        #expect(p.name == "Git log")
        #expect(p.side == .right)
        #expect(p.refreshSeconds == 10)
    }

    @Test func plainCommand() {
        let p = PanelCodeParser.parse("$ docker ps")
        #expect(p.kind == .command)
        #expect(p.code == "docker ps")
    }

    @Test func manifestRoundTrip() {
        var panel = CustomPanel(name: "Notes", kind: .web, code: "<textarea></textarea>")
        panel.allowCommands = true
        let back = PanelCodeParser.parse(PanelCodeParser.manifest(for: panel, side: .left))
        #expect(back.kind == .web && back.code == panel.code && back.side == .left && back.allowCommands == true)
    }

    @Test func dockMoves() {
        var l = LayoutSettings()
        l.move(PanelID.system, to: .right)
        #expect(l.leftPanels == [PanelID.files] && l.rightPanels == [PanelID.system])
        l.move(PanelID.system, to: .left, at: 0)
        #expect(l.leftPanels == [PanelID.system, PanelID.files] && l.rightPanels.isEmpty)
        #expect(l.side(of: PanelID.files) == .left)
    }
}

@Suite struct SyntaxTests {
    private func kinds(_ text: String, _ lang: Language) -> [String: TokenKind] {
        var out: [String: TokenKind] = [:]
        for t in SyntaxHighlighter.tokens(in: text, language: lang) {
            out[(text as NSString).substring(with: t.range)] = t.kind
        }
        return out
    }

    @Test func swiftStringsBeatComments() {
        let k = kinds("let url = \"http://x\" // note\nfunc go() {}", .swift)
        #expect(k["let"] == .keyword)
        #expect(k["\"http://x\""] == .string)
        #expect(k["// note"] == .comment)
        #expect(k["go"] == .function)
    }

    @Test func pythonAndShell() {
        let k = kinds("def run(x):\n    return None  # done", .python)
        #expect(k["def"] == .keyword && k["None"] == .constant && k["# done"] == .comment)
        let s = kinds("echo \"$HOME\" # hi\nexport PATH=$PATH:/x", .shell)
        #expect(s["# hi"] == .comment && s["$PATH"] == .variable && s["export"] == .keyword)
    }

    @Test func everyLanguageCompiles() {
        for lang in Language.allCases {
            _ = SyntaxHighlighter.tokens(in: "x = 1 // a \"b\" # c", language: lang)
        }
        #expect(Language.detect(fileName: "main.swift") == .swift)
        #expect(Language.detect(fileName: ".zshrc") == .shell)
        #expect(Language.detect(fileName: "run", firstLine: "#!/usr/bin/env python3") == .python)
    }

    @Test func outline() {
        let swift = "struct A {\n    func b() {}\n}\nextension A {}\n"
        let syms = OutlineExtractor.symbols(in: swift, language: .swift)
        #expect(syms.map(\.name) == ["A", "b", "A"])
        #expect(syms[1].line == 2 && syms[0].kind == .type)
        let md = OutlineExtractor.symbols(in: "# Title\ntext\n```\n# not a heading\n```\n## Sub", language: .markdown)
        #expect(md.map(\.name) == ["Title", "Sub"])
        let py = OutlineExtractor.symbols(in: "class K:\n    def m(self):\n        pass\n", language: .python)
        #expect(py.map(\.name) == ["K", "m"])
    }
}

@Suite struct MigrationTests {
    @Test func v1ResetsLookButKeepsTheRest() throws {
        let json = #"{"version": 1, "appearance": {"themeID": "retro-green"}, "effects": {"glow": {"enabled": true}}, "keybindings": {"newTab": "cmd+shift+n"}, "terminal": {"font": {"size": 16}}}"#
        var s = try JSONMerge.decodeMerged(AppSettings.self, from: Data(json.utf8), defaults: AppSettings())
        s.version = 1
        let m = s.migrated()
        #expect(m.version == AppSettings.currentVersion)
        #expect(m.appearance.themeID == "graphite")
        #expect(!m.effects.glow.enabled)
        #expect(m.keybindings["newTab"] == "cmd+shift+n")
        #expect(m.terminal.font.size == 16)
    }
}
