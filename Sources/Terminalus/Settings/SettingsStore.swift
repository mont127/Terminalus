import AppKit
import Observation
import TerminalusCore

/// Owns AppSettings: loads settings.json (merged over defaults), saves edits (debounced, atomic),
/// and live-reloads external edits. A malformed file never gets overwritten; the last good settings
/// stay active and `loadError` explains the problem.
@MainActor
@Observable
final class SettingsStore {
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            onChange?(oldValue, settings)
            if !applyingFromDisk { scheduleSave() }
        }
    }

    /// Called after every change (UI edits and external file edits alike).
    @ObservationIgnored var onChange: ((AppSettings, AppSettings) -> Void)?

    /// Set when settings.json could not be parsed; shown as a banner.
    var loadError: String?
    /// Safe mode (⌥ held at launch): defaults only, nothing is read or written.
    let safeMode: Bool

    @ObservationIgnored private var applyingFromDisk = false
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var lastWritten: Data?
    @ObservationIgnored private let saveDebouncer = Debouncer(delay: 0.35)
    @ObservationIgnored private let reloadDebouncer = Debouncer(delay: 0.15)
    /// True while the file on disk is malformed; saving is suspended so the user's text is not clobbered.
    @ObservationIgnored private var fileIsBroken = false

    var fileURL: URL { Paths.settingsFile }

    init(safeMode: Bool) {
        self.safeMode = safeMode
        self.settings = AppSettings()
        guard !safeMode else { return }
        Paths.ensureDirectories()
        loadFromDisk(initial: true)
        watcher = FileWatcher(url: fileURL) { [weak self] in
            Task { @MainActor in self?.reloadDebouncer.call { self?.loadFromDisk(initial: false) } }
        }
    }

    // MARK: Loading

    func loadFromDisk(initial: Bool) {
        guard !safeMode else { return }
        guard let data = try? Data(contentsOf: fileURL) else {
            if initial { writeNow() }
            return
        }
        if !initial, data == lastWritten { return }
        do {
            var decoded = try JSONMerge.decodeMerged(AppSettings.self, from: data, defaults: AppSettings())
            // An older file: keep a copy, then upgrade it.
            if (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["version"] as? Int ?? 1 < AppSettings.currentVersion {
                let backup = fileURL.deletingLastPathComponent().appendingPathComponent("settings-v1-backup.json")
                if !FileManager.default.fileExists(atPath: backup.path) { try? data.write(to: backup) }
                decoded.version = 1
                decoded = decoded.migrated()
                lastWritten = nil
                DispatchQueue.main.async { [weak self] in self?.writeNow() }
            }
            loadError = nil
            fileIsBroken = false
            if decoded != settings {
                applyingFromDisk = true
                settings = decoded
                applyingFromDisk = false
            }
        } catch {
            fileIsBroken = true
            loadError = "settings.json has an error, so the last good settings are still in use. \(error.localizedDescription)"
        }
    }

    // MARK: Saving

    private func scheduleSave() {
        guard !safeMode else { return }
        saveDebouncer.call { [weak self] in
            Task { @MainActor in self?.writeNow() }
        }
    }

    func writeNow() {
        guard !safeMode, !fileIsBroken else { return }
        do {
            let data = try JSONMerge.prettyEncode(settings)
            if data == lastWritten, FileManager.default.fileExists(atPath: fileURL.path) { return }
            lastWritten = data
            try data.write(to: fileURL, options: .atomic)
        } catch {
            loadError = "Could not save settings: \(error.localizedDescription)"
        }
    }

    // MARK: Helpers

    func update(_ body: (inout AppSettings) -> Void) {
        var s = settings
        body(&s)
        settings = s
    }

    func resetToDefaults() {
        fileIsBroken = false
        loadError = nil
        settings = AppSettings()
        writeNow()
    }

    func export(to url: URL) throws {
        try JSONMerge.prettyEncode(settings).write(to: url, options: .atomic)
    }

    func importSettings(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoded = try JSONMerge.decodeMerged(AppSettings.self, from: data, defaults: AppSettings())
        fileIsBroken = false
        loadError = nil
        settings = decoded
        writeNow()
    }

    /// Discards the broken file state and overwrites settings.json with the settings in use.
    func overwriteBrokenFile() {
        fileIsBroken = false
        loadError = nil
        lastWritten = nil
        writeNow()
    }
}
