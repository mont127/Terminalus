import AppKit
import Observation
import TerminalusCore

/// Built-in themes plus user themes stored as JSON (or .itermcolors) in the themes folder.
@MainActor
@Observable
final class ThemeCatalog {
    private(set) var userThemes: [Theme] = []
    var lastError: String?

    init() {
        reload()
    }

    var all: [Theme] {
        let userIDs = Set(userThemes.map(\.id))
        return Theme.builtins.filter { !userIDs.contains($0.id) } + userThemes
    }

    func theme(id: String) -> Theme {
        userThemes.first { $0.id == id } ?? Theme.builtin(id: id) ?? Theme.builtin(id: Theme.defaultID) ?? Theme.builtins[0]
    }

    func isUserTheme(_ id: String) -> Bool { userThemes.contains { $0.id == id } }

    func reload() {
        let dir = Paths.themesDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var themes: [Theme] = []
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            switch url.pathExtension.lowercased() {
            case "json":
                if let data = try? Data(contentsOf: url), let t = try? JSONDecoder().decode(Theme.self, from: data) {
                    themes.append(t)
                }
            case "itermcolors":
                if let data = try? Data(contentsOf: url),
                   let t = try? ITermColors.importTheme(data: data, name: url.deletingPathExtension().lastPathComponent) {
                    themes.append(t)
                }
            default:
                break
            }
        }
        userThemes = themes
    }

    func save(_ theme: Theme) {
        Paths.ensureDirectories()
        do {
            let data = try JSONMerge.prettyEncode(theme)
            try data.write(to: fileURL(for: theme.id), options: .atomic)
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func delete(id: String) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
        reload()
    }

    @discardableResult
    func importITermColors(from url: URL) throws -> Theme {
        let data = try Data(contentsOf: url)
        var theme = try ITermColors.importTheme(data: data, name: url.deletingPathExtension().lastPathComponent)
        theme.id = uniqueID(theme.id)
        save(theme)
        return theme
    }

    func uniqueID(_ base: String) -> String {
        var id = base
        var n = 2
        while all.contains(where: { $0.id == id }) {
            id = "\(base)-\(n)"
            n += 1
        }
        return id
    }

    private func fileURL(for id: String) -> URL {
        Paths.themesDirectory.appendingPathComponent(id).appendingPathExtension("json")
    }
}
