# Terminalus

A native macOS terminal with a file tree that is always visible and follows your shell, live system
stats, and almost everything customizable.

- **Real terminal.** Built on [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (xterm/VT emulation):
  vim, htop, tmux, mouse reporting, 256 colors and truecolor, find bar, links, and a login shell that
  loads your normal dotfiles.
- **Tabs and split panes.** Split right or down, move focus between panes, zoom a pane, drag the dividers,
  rename tabs, and reorder them by dragging.
- **File tree.** By default the tree starts at `/`, opens the folders down to the current directory,
  highlights it, and follows every `cd` in the focused pane (nested shells too).
  - Root can also be the current directory, your home folder or the git repository root.
  - Git status badges on files and folders, plus the branch and ahead/behind counts.
  - Updates live as files change (FSEvents).
  - Double-click to `cd` or open a file, drag a file into the terminal to insert its path, press Space for
    Quick Look, and right-click for a context menu.
- **Side panels you can move.** Files, System, Outline and your own panels sit in a left and a right
  dock. Drag a panel's title bar to the other side (or use its ••• menu), reorder, resize, collapse or
  hide panels. View → Panels lists them all.
- **Import Window Code.** Paste HTML/CSS/JavaScript (code in ``` fences is fine), a JSON manifest or a
  plain shell command, and it becomes a working side panel. Web panels get a small `terminalus` API
  (current directory, live stats, git, theme colors, running commands with permission); command panels
  refresh their colored output on a timer. Templates are in the import window.
- **IDE mode.** Running `nano file` (or pico, micro, vim, vi, nvim, emacs — configurable) opens the file
  in a built-in editor with the terminal docked underneath. The shell waits until you close the file,
  just like the real editor, and closing the last file tab returns to the plain terminal.
  - Syntax highlighting for ~25 languages, line numbers, auto-indent, bracket pairs, ⌘/ comments,
    ⌘L go to line, find, an Outline panel, and ⌘R to run the file.
  - "Open in nano/vim" hands the file back to the real editor; `command nano` always runs the real one.
- **Live stats.** In the System panel (either side) or as a strip under the terminal:
  - Session (command, timer, exit code, git status, processes)
  - CPU, per-core heatmap (efficiency/performance cores), memory breakdown and pressure
  - GPU, network, disk space and I/O, top processes
  - System info, thermal state, clock, battery (hidden on Macs without one)
  - Temperature sensors (experimental)
- **Customization.** 30 themes (Graphite by default) plus a full theme editor and `.itermcolors` import/export, fonts, cursor,
  transparency, blur, background images, animated gradients (drawn by Core Animation), text glow, CRT
  scanlines, vignette, grain and flicker. You can also change:
  - the layout: which panels sit on which side, dock widths, the stats strip, tab bar style;
  - tree behavior and per-widget chart styles;
  - profiles: shell, arguments, environment, startup command, and per-profile theme, font and tab color;
  - every key binding;
  - the command palette (⇧⌘P).

## Build & run

Requirements: macOS 14+, and the Swift toolchain from the Command Line Tools or Xcode.

```bash
scripts/build-app.sh --open        # release build → build/Terminalus.app, then launch it
scripts/build-app.sh --install     # also copy it to /Applications
scripts/build-app.sh --debug       # faster debug build
scripts/test.sh                    # unit tests (swift-testing)
```

`scripts/bootstrap-swiftterm.sh` runs automatically the first time. It vendors SwiftTerm 1.20.0 into
`Vendor/SwiftTerm` and patches it to ship its Metal shader as source. The Command Line Tools have no
`metal` compiler; SwiftTerm compiles the shader at runtime if you turn on the Metal renderer.

The build uses the macOS 26 SDK when it is installed. The macOS 27 SDK in the Command Line Tools turns
SwiftUI's `@State` into a compiler macro whose plugin only ships with full Xcode.

**No Apple Developer account needed.** The build script signs the app *ad-hoc* (`codesign --sign -`).
That is free and only there because Apple Silicon refuses to launch completely unsigned apps. It is not a
developer signature and the app is not notarized, so:

- An app you build yourself runs normally.
- A copy downloaded from the internet is blocked by Gatekeeper the first time. Right-click it → **Open**,
  or run `xattr -dr com.apple.quarantine Terminalus.app`.
- macOS may ask again for Desktop/Documents/Downloads access after a rebuild, because every ad-hoc build
  has a new signature. If you do have a certificate, `SIGN_IDENTITY="Name" scripts/build-app.sh` uses it.

## Keyboard shortcuts (defaults — all remappable in Settings → Key Bindings)

| Action | Keys | Action | Keys |
|---|---|---|---|
| New window / tab | ⌘N / ⌘T | Command palette | ⇧⌘P |
| Split right / down | ⌘D / ⇧⌘D | Settings / settings.json | ⌘, / ⌥⌘, |
| Close pane / tab / window | ⌘W / ⌥⌘W / ⇧⌘W | Show/hide left side / System | ⌘B / ⌥⌘S |
| Next / previous pane | ⌘] / ⌘[ | Show/hide right side | ⌥⌘B |
| Focus pane by direction | ⌥⌘ + arrows | Focus file tree | ⇧⌘E |
| Zoom pane | ⇧⌘↩ | Reveal cwd in tree | ⇧⌘R |
| Next / previous tab | ⇧⌘] / ⇧⌘[ | Show hidden files | ⇧⌘. |
| Tab 1–9 | ⌘1 … ⌘9 | Next / previous theme | ⌥⌘] / ⌥⌘[ |
| Bigger / smaller / reset font | ⌘= / ⌘- / ⌘0 | Toggle effects / glow | ⌥⌘E / ⌥⌘G |
| Find / next / previous | ⌘F / ⌘G / ⇧⌘G | Toggle transparency | ⌘U |
| Clear buffer | ⌘K | Copy cwd / open in Finder | ⇧⌘C / ⇧⌘O |
| Open/close the editor | ⇧⌘I | Open file in editor | ⌘O |
| Save / Save As (editor) | ⌘S / ⇧⌘S | Run file | ⌘R |
| Go to line / comment | ⌘L / ⌘/ | Import Window Code | ⌥⌘I |

Keys inside the file tree:

- Return runs the double-click action.
- Space opens Quick Look.
- ⌘C copies the path.
- Esc returns focus to the terminal.

## Settings

Everything is stored in `~/Library/Application Support/Terminalus/settings.json`. The Settings window
(⌘,) edits the same file.

- Changes you make in any editor apply live.
- Keys you leave out use their defaults.
- If the file has an error, a banner explains it and the last good settings stay active. The file is
  never overwritten while it is broken.
- Hold ⌥ while launching to start in safe mode (defaults only, nothing read or written).

```jsonc
{
  "appearance": { "themeID": "tokyo-night", "uiFontDesign": "monospaced", "cornerRadius": 12 },
  "terminal":   { "font": { "family": "JetBrains Mono", "size": 14 }, "cursor": { "shape": "block" } },
  "window":     { "titlebar": "transparent", "backgroundOpacity": 0.8, "blur": true },
  "background": { "gradient": { "style": "aurora", "speed": 0.1, "opacity": 0.2 } },
  "effects":    { "glow": { "radius": 6 }, "scanlines": { "enabled": true } },
  "layout":     { "leftPanels": ["files"], "rightPanels": ["system"], "statsStrip": false },
  "editor":     { "interceptedCommands": ["nano", "vim"], "tabWidth": 2, "wordWrap": true },
  "tree":       { "rootMode": "gitRoot", "showHidden": true, "ignore": [".git", "node_modules"] },
  "stats":      { "refreshInterval": 1, "widgets": [{ "kind": "cpu", "style": "ring" }, { "kind": "network" }] },
  "profiles":   [{ "id": "default", "name": "Default" }, { "id": "bash", "name": "Bash", "shellPath": "/bin/bash", "tabColor": "#36f9f6" }],
  "keybindings": { "newTab": "cmd+shift+n" }
}
```

User themes live in `~/Library/Application Support/Terminalus/themes/`, as `.json` or `.itermcolors` files.
Custom panels live in `…/Terminalus/panels/`, one JSON file each.

## Panel code

A web panel is any HTML — a fragment or a whole page. It runs in its own web view with these extras:

```js
terminalus.cwd, terminalus.stats, terminalus.git, terminalus.theme      // current values
terminalus.on('cwd' | 'stats' | 'git' | 'theme', value => { … })      // live updates
await terminalus.run('git log -5 --oneline')  // {stdout, stderr, code} — needs "Allow commands"
terminalus.send('make test\r')                // types into the terminal — needs "Allow commands"
terminalus.cd('~/src'); terminalus.open('https://…'); terminalus.notify('Done', 'Build finished')
```

CSS variables follow the theme: `--bg --fg --accent --accent2 --muted --border --panel --font-ui
--font-mono --ansi-0 … --ansi-15`. `localStorage` is kept per panel.

A JSON manifest can set everything at once:

```json
{ "name": "Git log", "command": "git log --oneline --graph --color=always -20", "refresh": 10, "side": "right" }
```

## How directory tracking works

zsh and bash start with a small integration script (`ZDOTDIR` shim / `--rcfile`). The script loads your
normal startup files, then reports the working directory (OSC 7), each command's start and exit
status and the shell's PATH to Terminalus. It also defines the editor functions used by IDE mode. For other shells, or for nested shells, Terminalus reads the foreground process's
working directory from the kernel instead. Turn integration off in Settings → General.

## Development

- `Sources/TerminalusCore`: settings model, themes, shell integration, git, file-system watching and the
  system samplers (Foundation/IOKit only; unit-tested in `Tests/`).
- `Sources/Terminalus`: the AppKit/SwiftUI app.
- `TERMINALUS_HOME=<dir>` points a copy of the app at its own settings/panels folder.
- Launching with `--automation <dir>` enables a testing hook. The app runs JSON command files dropped into
  `<dir>`: type text, run actions, send key events, and take snapshots or state dumps. See
  `Sources/Terminalus/Util/Automation.swift`.

## License

Terminalus is licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for third-party
software (SwiftTerm, MIT License).
