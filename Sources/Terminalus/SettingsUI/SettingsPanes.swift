import AppKit
import SwiftTerm
import SwiftUI
import UniformTypeIdentifiers
import TerminalusCore

private var store: SettingsStore { AppState.shared.settingsStore }

// MARK: - Themes (editor)

struct ThemesPane: View {
    @State private var editing: Theme?
    @State private var selectedID: String = AppState.shared.settings.appearance.themeID
    @State private var message: String?

    var body: some View {
        let catalog = AppState.shared.themes
        HSplitView {
            List(selection: Binding(get: { selectedID }, set: { if let v = $0 { selectedID = v; editing = nil } })) {
                Section("Built-in") {
                    ForEach(Theme.builtins.filter { !catalog.isUserTheme($0.id) }) { t in row(t).tag(t.id) }
                }
                Section("Yours") {
                    ForEach(catalog.userThemes) { t in row(t).tag(t.id) }
                }
            }
            .frame(minWidth: 200, idealWidth: 230)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    let theme = editing ?? catalog.theme(id: selectedID)
                    ThemePreview(theme: theme).frame(height: 190)
                    HStack {
                        Button("Use Theme") {
                            store.update {
                                $0.appearance.themeID = theme.id
                                $0.appearance.followSystemAppearance = false
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        if editing == nil {
                            Button("Duplicate & Edit") {
                                let id = catalog.uniqueID("user-" + theme.id)
                                editing = theme.duplicated(id: id, name: theme.name + " Custom")
                            }
                            if catalog.isUserTheme(theme.id) {
                                Button("Edit") { editing = theme }
                                Button("Delete", role: .destructive) {
                                    catalog.delete(id: theme.id)
                                    selectedID = Theme.defaultID
                                    AppState.shared.themesChanged()
                                    MainMenu.install()
                                }
                            }
                        } else {
                            Button("Save") { save() }
                            Button("Cancel") { editing = nil }
                        }
                        Spacer()
                    }
                    HStack {
                        Button("Import .itermcolors…") { importITerm() }
                        Button("Export…") { export(theme) }
                        Spacer()
                    }
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    if editing != nil { editor }
                }
                .padding(18)
            }
            .frame(minWidth: 420)
        }
    }

    private func row(_ t: Theme) -> some View {
        let r = ResolvedTheme(t)
        return HStack {
            HStack(spacing: 1) {
                ForEach([1, 2, 3, 4, 5, 6], id: \.self) { i in Rectangle().fill(r.ansi[i + 8].color).frame(width: 5, height: 12) }
            }
            .padding(3)
            .background(r.background.color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(t.name)
            if t.id == store.settings.appearance.themeID { Image(systemName: "checkmark").foregroundStyle(.secondary) }
        }
    }

    private var editor: some View {
        let names = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]
        return Form {
            Section("Name") {
                TextField("Name", text: Binding(get: { editing?.name ?? "" }, set: { editing?.name = $0 }))
            }
            Section("Terminal") {
                HexColorPicker(title: "Foreground", hex: bind(\.foreground))
                HexColorPicker(title: "Background", hex: bind(\.background))
                HexColorPicker(title: "Cursor", hex: bind(\.cursor))
                HexColorPicker(title: "Selection", hex: bind(\.selection))
                optionalHex("Cursor text", \.cursorText)
                optionalHex("Selected text", \.selectionText)
                optionalHex("Bold text", \.bold)
                optionalHex("Links", \.link)
            }
            Section("ANSI colors") {
                Grid(horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("")
                        Text("Normal").font(.caption).foregroundStyle(.secondary)
                        Text("Bright").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(0..<8, id: \.self) { i in
                        GridRow {
                            Text(names[i])
                            ansiPicker(i)
                            ansiPicker(i + 8)
                        }
                    }
                }
            }
            Section("Interface colors (optional)") {
                chromeHex("Accent", \.accent)
                chromeHex("Second accent", \.accent2)
                chromeHex("Glow", \.glow)
                chromeHex("Sidebar", \.sidebarBackground)
                chromeHex("Panels", \.panelBackground)
                chromeHex("Borders", \.border)
                chromeHex("Secondary text", \.secondaryText)
                chromeHex("Success", \.success)
                chromeHex("Warning", \.warning)
                chromeHex("Danger", \.danger)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 900)
    }

    private func bind(_ kp: WritableKeyPath<Theme, String>) -> Binding<String> {
        Binding(get: { editing?[keyPath: kp] ?? "#000000" }, set: { editing?[keyPath: kp] = $0 })
    }

    private func optionalHex(_ title: String, _ kp: WritableKeyPath<Theme, String?>) -> some View {
        let fallback = editing.map { RGBA(hex: $0.foreground) ?? .white } ?? .white
        return OptionalColorRow(title: title, hex: Binding(get: { editing?[keyPath: kp] }, set: { editing?[keyPath: kp] = $0 }), fallback: fallback)
    }

    private func chromeHex(_ title: String, _ kp: WritableKeyPath<ThemeChrome, String?>) -> some View {
        let resolved = editing.map { ResolvedTheme($0) }
        let fallback: RGBA = resolved.map { r in
            switch kp {
            case \ThemeChrome.accent: r.accent
            case \ThemeChrome.accent2: r.accent2
            case \ThemeChrome.glow: r.glow
            case \ThemeChrome.sidebarBackground: r.sidebarBackground
            case \ThemeChrome.panelBackground: r.panelBackground
            case \ThemeChrome.border: r.border
            case \ThemeChrome.secondaryText: r.secondaryText
            case \ThemeChrome.success: r.success
            case \ThemeChrome.warning: r.warning
            default: r.danger
            }
        } ?? .white
        return OptionalColorRow(title: title, hex: Binding(
            get: { editing?.chrome?[keyPath: kp] },
            set: { v in
                if editing?.chrome == nil { editing?.chrome = ThemeChrome() }
                editing?.chrome?[keyPath: kp] = v
            }
        ), fallback: fallback)
    }

    private func ansiPicker(_ i: Int) -> some View {
        ColorPicker("", selection: Binding(
            get: { RGBA(hex: editing?.ansi[safe: i] ?? "")?.color ?? .black },
            set: { c in
                guard var t = editing else { return }
                while t.ansi.count < 16 { t.ansi.append("#808080") }
                t.ansi[i] = c.rgba.hex
                editing = t
            }
        ), supportsOpacity: false)
        .labelsHidden()
    }

    private func save() {
        guard let t = editing else { return }
        let catalog = AppState.shared.themes
        catalog.save(t)
        selectedID = t.id
        editing = nil
        store.update {
            $0.appearance.themeID = t.id
            $0.appearance.followSystemAppearance = false
        }
        AppState.shared.themesChanged()
        MainMenu.install()
        message = "Saved \(t.name)"
    }

    private func importITerm() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "itermcolors") ?? .propertyList, .propertyList]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var names: [String] = []
        for url in panel.urls {
            do {
                let t = try AppState.shared.themes.importITermColors(from: url)
                names.append(t.name)
                selectedID = t.id
            } catch {
                message = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        if !names.isEmpty {
            message = "Imported \(names.joined(separator: ", "))"
            MainMenu.install()
        }
    }

    private func export(_ theme: Theme) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = theme.name + ".itermcolors"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if url.pathExtension.lowercased() == "json" {
                try JSONMerge.prettyEncode(theme).write(to: url)
            } else {
                try ITermColors.export(theme).write(to: url)
            }
            message = "Exported \(url.lastPathComponent)"
        } catch {
            message = error.localizedDescription
        }
    }
}

/// A real SwiftTerm view (no process) fed with sample output, so theme edits preview exactly.
struct ThemePreview: NSViewRepresentable {
    let theme: Theme

    func makeNSView(context: Context) -> TerminalView {
        let v = TerminalView(frame: NSRect(x: 0, y: 0, width: 500, height: 190))
        v.font = FontResolver.terminalFont(family: store.settings.terminal.font.family, size: 12, weight: store.settings.terminal.font.weight)
        return v
    }

    func updateNSView(_ v: TerminalView, context: Context) {
        let r = ResolvedTheme(theme)
        v.installColors(r.ansi.map(\.stColor))
        v.nativeForegroundColor = r.foreground.nsColor
        v.nativeBackgroundColor = r.background.nsColor
        v.caretColor = r.cursor.nsColor
        v.selectedTextBackgroundColor = r.selection.nsColor
        v.getTerminal().resetToInitialState()
        var s = "\u{1b}[2J\u{1b}[H"
        s += "\u{1b}[1;32m❯\u{1b}[0m \u{1b}[34m~/projects/terminalus\u{1b}[0m on \u{1b}[35m main\u{1b}[0m \u{1b}[33m●\u{1b}[0m\r\n"
        s += "\u{1b}[1m$\u{1b}[0m ls -la\r\n"
        s += "\u{1b}[1;34mSources\u{1b}[0m  \u{1b}[1;34mTests\u{1b}[0m  \u{1b}[32mbuild.sh\u{1b}[0m  README.md  \u{1b}[31mcore.dump\u{1b}[0m\r\n"
        for row in 0..<2 {
            for i in 0..<8 {
                s += "\u{1b}[\(row == 0 ? 40 + i : 100 + i)m  \u{1b}[0m"
            }
            s += "   "
            for i in 0..<8 {
                s += "\u{1b}[\(row == 0 ? 30 + i : 90 + i)m■ \u{1b}[0m"
            }
            s += "\r\n"
        }
        s += "\u{1b}[1mbold\u{1b}[0m \u{1b}[3mitalic\u{1b}[0m \u{1b}[4munderline\u{1b}[0m \u{1b}[7mreverse\u{1b}[0m \u{1b}[38;2;255;120;50mtruecolor\u{1b}[0m\r\n"
        s += "\u{1b}[1;31merror:\u{1b}[0m something failed  \u{1b}[1;33mwarning:\u{1b}[0m careful  \u{1b}[1;32m✓ ok\u{1b}[0m\r\n$ "
        v.feed(text: s)
    }
}

// MARK: - Stats & widgets

struct StatsPane: View {
    var body: some View {
        let s = store.settings
        Form {
            Section("Sampling") {
                SliderRow(title: "Refresh every", value: store.binding(\.stats.refreshInterval), range: 0.25...10, step: 0.25) { String(format: "%.2f s", $0) }
                EnumPicker(title: "Process list source", value: store.binding(\.stats.processBackend))
                Stepper("Processes shown: \(s.stats.processCount)", value: store.binding(\.stats.processCount), in: 1...30)
                EnumPicker(title: "Sort processes by", value: store.binding(\.stats.processSort))
            }
            Section("Units & display") {
                EnumPicker(title: "Temperature", value: store.binding(\.stats.temperatureUnit))
                EnumPicker(title: "Network", value: store.binding(\.stats.networkUnit))
                Toggle("Widget headers", isOn: store.binding(\.stats.showWidgetHeaders))
                Toggle("Icons in widget headers", isOn: store.binding(\.stats.showWidgetIcons))
                Toggle("A different color for every widget", isOn: store.binding(\.stats.colorfulCharts))
                Toggle("Glowing charts", isOn: store.binding(\.stats.chartGlow))
                Toggle("24-hour clock", isOn: store.binding(\.stats.clock24h))
            }
            Section("Widgets (drag to reorder)") {
                List {
                    ForEach(s.stats.normalizedWidgets) { w in
                        WidgetEditorRow(config: w)
                    }
                    .onMove { from, to in
                        store.update { st in
                            var list = st.stats.normalizedWidgets
                            list.move(fromOffsets: from, toOffset: to)
                            st.stats.widgets = list
                        }
                    }
                }
                .frame(minHeight: 420)
                Button("Reset Widgets") { store.update { $0.stats.widgets = StatsSettings.defaultWidgets } }
            }
        }
        .formStyle(.grouped)
    }
}

private struct WidgetEditorRow: View {
    let config: WidgetConfig

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            Toggle("", isOn: bind(\.enabled)).labelsHidden().toggleStyle(.switch).controlSize(.mini)
            Image(systemName: config.kind.symbol).frame(width: 18)
            Text(config.kind.label).frame(width: 170, alignment: .leading)
            if config.kind.supportedStyles.count > 1 {
                Picker("", selection: bind(\.style)) {
                    ForEach(config.kind.supportedStyles) { st in Text(st.label).tag(st) }
                }
                .labelsHidden()
                .frame(width: 100)
            } else {
                Spacer().frame(width: 100)
            }
            Picker("", selection: bind(\.size)) {
                ForEach(WidgetSize.allCases) { sz in Text(sz.label).tag(sz) }
            }
            .labelsHidden()
            .frame(width: 95)
            Stepper("\(config.history)s", value: bind(\.history), in: 10...600, step: 10)
                .frame(width: 90)
                .help("History length")
            Toggle("", isOn: Binding(get: { config.color != nil }, set: { on in
                update { $0.color = on ? AppState.shared.uiTheme.accent.hex : nil }
            }))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .help("Custom color")
            if config.color != nil {
                ColorPicker("", selection: Binding(get: { RGBA(hex: config.color ?? "")?.color ?? .white },
                                                   set: { c in update { $0.color = c.rgba.hex } }))
                    .labelsHidden()
            }
        }
    }

    private func update(_ body: (inout WidgetConfig) -> Void) {
        store.update { st in
            var list = st.stats.normalizedWidgets
            if let i = list.firstIndex(where: { $0.kind == config.kind }) { body(&list[i]) }
            st.stats.widgets = list
        }
    }

    private func bind<T>(_ kp: WritableKeyPath<WidgetConfig, T>) -> Binding<T> {
        Binding(get: { config[keyPath: kp] }, set: { v in update { $0[keyPath: kp] = v } })
    }
}

// MARK: - Profiles

struct ProfilesPane: View {
    @State private var selected: String = AppState.shared.settings.defaultProfileID

    var body: some View {
        let s = store.settings
        HSplitView {
            VStack(spacing: 0) {
                List(selection: Binding(get: { selected }, set: { if let v = $0 { selected = v } })) {
                    ForEach(s.profiles) { p in
                        HStack {
                            Circle().fill(RGBA(hex: p.tabColor ?? "")?.color ?? .secondary.opacity(0.4)).frame(width: 8, height: 8)
                            Text(p.name)
                            if p.id == s.defaultProfileID { Text("default").font(.caption).foregroundStyle(.secondary) }
                        }
                        .tag(p.id)
                    }
                }
                HStack {
                    Button { add() } label: { Image(systemName: "plus") }
                    Button { duplicate() } label: { Image(systemName: "plus.square.on.square") }
                    Button { remove() } label: { Image(systemName: "minus") }.disabled(s.profiles.count <= 1)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(minWidth: 190, idealWidth: 210)

            if let idx = s.profiles.firstIndex(where: { $0.id == selected }) {
                ProfileEditor(index: idx)
            } else {
                Text("Select a profile").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func add() {
        let p = Profile(id: UUID().uuidString, name: "New Profile")
        store.update { $0.profiles.append(p) }
        selected = p.id
    }

    private func duplicate() {
        guard var p = store.settings.profiles.first(where: { $0.id == selected }) else { return }
        p.id = UUID().uuidString
        p.name += " Copy"
        store.update { $0.profiles.append(p) }
        selected = p.id
    }

    private func remove() {
        guard store.settings.profiles.count > 1 else { return }
        store.update { s in
            s.profiles.removeAll { $0.id == selected }
            if !s.profiles.contains(where: { $0.id == s.defaultProfileID }) { s.defaultProfileID = s.profiles[0].id }
        }
        selected = store.settings.profiles[0].id
    }
}

private struct ProfileEditor: View {
    let index: Int

    var body: some View {
        let p = store.settings.profiles[index]
        Form {
            Section("Profile") {
                TextField("Name", text: bind(\.name))
                Toggle("Default profile", isOn: Binding(get: { store.settings.defaultProfileID == p.id },
                                                        set: { if $0 { store.update { $0.defaultProfileID = p.id } } }))
                OptionalColorRow(title: "Tab color", hex: bind(\.tabColor), fallback: AppState.shared.uiTheme.accent)
            }
            Section("Shell") {
                TextField("Shell (empty = your login shell: \(ShellLauncher.userShell))", text: bind(\.shellPath))
                TextField("Arguments (space separated)", text: Binding(get: { p.args.joined(separator: " ") },
                                                                       set: { v in update { $0.args = v.split(separator: " ").map(String.init) } }))
                Toggle("Login shell", isOn: bind(\.login))
                TextField("Startup command", text: bind(\.startupCommand))
                EnumPicker(title: "Working directory", value: bind(\.workingDirectory))
                if p.workingDirectory == .custom {
                    HStack {
                        TextField("Folder", text: bind(\.customDirectory))
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            if panel.runModal() == .OK, let u = panel.url { update { $0.customDirectory = u.path } }
                        }
                    }
                }
                LabeledContent("Environment (KEY=value per line)") {
                    TextEditor(text: Binding(
                        get: { p.environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") },
                        set: { v in
                            var env: [String: String] = [:]
                            for line in v.split(separator: "\n") {
                                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                                if parts.count == 2, !parts[0].trimmingCharacters(in: .whitespaces).isEmpty {
                                    env[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1]
                                }
                            }
                            update { $0.environment = env }
                        }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 70)
                }
            }
            Section("Look (overrides)") {
                Picker("Theme", selection: bind(\.themeID)) {
                    Text("Same as app").tag(String?.none)
                    ForEach(AppState.shared.themes.all) { t in Text(t.name).tag(String?.some(t.id)) }
                }
                Picker("Font", selection: bind(\.fontFamily)) {
                    Text("Same as app").tag(String?.none)
                    Text("System Monospaced").tag(String?.some(""))
                    ForEach(FontResolver.monospacedFamilies, id: \.self) { f in Text(f).tag(String?.some(f)) }
                }
                LabeledContent("Font size") {
                    HStack {
                        Toggle("Custom", isOn: Binding(get: { p.fontSize != nil },
                                                       set: { on in update { $0.fontSize = on ? store.settings.terminal.font.size : nil } }))
                            .toggleStyle(.checkbox)
                        if let size = p.fontSize {
                            Stepper(String(format: "%.1f pt", size), value: Binding(get: { size }, set: { v in update { $0.fontSize = v } }), in: 6...72, step: 0.5)
                        }
                    }
                }
                Picker("Cursor", selection: bind(\.cursorShape)) {
                    Text("Same as app").tag(CursorShape?.none)
                    ForEach(CursorShape.allCases) { c in Text(c.label).tag(CursorShape?.some(c)) }
                }
            }
            Section {
                Button("Open a New Tab with This Profile") {
                    if let ws = AppState.shared.activeWorkspace { ws.newTab(profileID: p.id) } else { AppState.shared.newWindow(profileID: p.id) }
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { MainMenu.install() }
    }

    private func update(_ body: (inout Profile) -> Void) {
        store.update { s in
            guard s.profiles.indices.contains(index) else { return }
            body(&s.profiles[index])
        }
    }

    private func bind<T>(_ kp: WritableKeyPath<Profile, T>) -> Binding<T> {
        Binding(get: { store.settings.profiles[safe: index]?[keyPath: kp] ?? Profile.defaultProfile[keyPath: kp] },
                set: { v in update { $0[keyPath: kp] = v } })
    }
}

// MARK: - Key bindings

struct KeyBindingsPane: View {
    @State private var filter = ""

    var body: some View {
        let bindings = AppState.shared.bindings
        let actions = AppAction.allCases.filter { filter.isEmpty || $0.title.localizedCaseInsensitiveContains(filter) }
        let conflicts = Dictionary(grouping: bindings, by: \.value).filter { $0.value.count > 1 }.keys
        Form {
            Section {
                TextField("Filter", text: $filter, prompt: Text("Search actions…"))
                Button("Reset All to Defaults") { store.update { $0.keybindings = [:] } }
            }
            ForEach(AppAction.Category.allCases, id: \.self) { cat in
                let list = actions.filter { $0.category == cat }
                if !list.isEmpty {
                    Section(cat.rawValue) {
                        ForEach(list) { a in
                            HStack {
                                Text(a.title)
                                Spacer()
                                if let c = bindings[a], conflicts.contains(c) {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help("Used by more than one action")
                                }
                                KeyRecorder(combo: bindings[a]) { newCombo in
                                    store.update { $0.keybindings[a.rawValue] = newCombo?.description ?? "" }
                                }
                                Button {
                                    store.update { $0.keybindings[a.rawValue] = nil }
                                } label: { Image(systemName: "arrow.uturn.backward") }
                                    .buttonStyle(.borderless)
                                    .help("Reset to \(KeyCombo(a.defaultBinding)?.symbolic ?? "none")")
                                    .disabled(store.settings.keybindings[a.rawValue] == nil)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Click, then press a shortcut. ⌫ clears, ⎋ cancels.
struct KeyRecorder: View {
    let combo: KeyCombo?
    let onChange: (KeyCombo?) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Press keys…" : (combo?.symbolic ?? "—"))
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 110)
        }
        .buttonStyle(.bordered)
        .tint(recording ? .accentColor : nil)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        KeybindingManager.shared.suspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if event.keyCode == 53 {
                    stop()
                } else if event.keyCode == 51 && event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                    onChange(nil)
                    stop()
                } else if let c = KeyCombo.from(event: event) {
                    onChange(c)
                    stop()
                }
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        KeybindingManager.shared.suspended = false
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }
}
