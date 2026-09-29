import Foundation

/// A launch profile: which shell to run and optional per-profile look overrides.
public struct Profile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// Empty means the user's login shell from the password database.
    public var shellPath: String = ""
    public var args: [String] = []
    public var login: Bool = true
    public var environment: [String: String] = [:]
    /// Typed into the shell right after it starts.
    public var startupCommand: String = ""
    public var workingDirectory: WorkingDirectoryMode = .inherit
    public var customDirectory: String = ""
    // Optional overrides of the global settings.
    public var themeID: String? = nil
    public var fontFamily: String? = nil
    public var fontSize: Double? = nil
    public var cursorShape: CursorShape? = nil
    /// Hex color shown on tabs that use this profile.
    public var tabColor: String? = nil

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public static let defaultProfile = Profile(id: "default", name: "Default")

    private enum CodingKeys: String, CodingKey {
        case id, name, shellPath, args, login, environment, startupCommand, workingDirectory, customDirectory
        case themeID, fontFamily, fontSize, cursorShape, tabColor
    }

    // Hand-written so a profile in settings.json may omit any key except `id`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        shellPath = try c.decodeIfPresent(String.self, forKey: .shellPath) ?? ""
        args = try c.decodeIfPresent([String].self, forKey: .args) ?? []
        login = try c.decodeIfPresent(Bool.self, forKey: .login) ?? true
        environment = try c.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        startupCommand = try c.decodeIfPresent(String.self, forKey: .startupCommand) ?? ""
        workingDirectory = try c.decodeIfPresent(WorkingDirectoryMode.self, forKey: .workingDirectory) ?? .inherit
        customDirectory = try c.decodeIfPresent(String.self, forKey: .customDirectory) ?? ""
        themeID = try c.decodeIfPresent(String.self, forKey: .themeID)
        fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily)
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize)
        cursorShape = try c.decodeIfPresent(CursorShape.self, forKey: .cursorShape)
        tabColor = try c.decodeIfPresent(String.self, forKey: .tabColor)
    }
}
