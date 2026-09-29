import Foundation

extension Theme {
    /// Themes that ship with Terminalus, in display order.
    public static let builtins: [Theme] = [
        // Graphite — the default: quiet graphite neutrals, one warm accent.
        Theme(
            id: "graphite", name: "Graphite",
            foreground: "#d4d7dd", background: "#15171b",
            cursor: "#f0a35e", cursorText: "#15171b",
            selection: "#3b414d", selectionText: nil,
            link: "#7fb0e6",
            ansi: [
                "#22252b", "#e06c6c", "#98c379", "#e5c07b", "#6fa3e0", "#c49ae8", "#5fb8c2", "#c8ccd4",
                "#5c6370", "#f28b82", "#b5d99c", "#f0d08c", "#8cb8f0", "#d6b4f5", "#7fd0d8", "#eef0f3",
            ],
            chrome: ThemeChrome(
                accent: "#f0a35e", accent2: "#7fb0e6",
                sidebarBackground: "#101216", panelBackground: "#1b1e23",
                border: "#ffffff12", text: "#d4d7dd", secondaryText: "#868d99",
                success: "#98c379", warning: "#e5c07b", danger: "#e06c6c"
            )
        ),
        // Graphite Light — daylight counterpart.
        Theme(
            id: "graphite-light", name: "Graphite Light",
            foreground: "#2b2f36", background: "#f6f6f4",
            cursor: "#c46a1c", cursorText: "#f6f6f4",
            selection: "#d9dde4", selectionText: nil,
            link: "#2f6fb8",
            ansi: [
                "#2b2f36", "#c43d3d", "#3f8a2e", "#9a6b00", "#2f6fb8", "#8a4bb8", "#1d7f8c", "#b8bcc4",
                "#6b717c", "#d64f4f", "#4f9e3c", "#b07d0a", "#3f82cc", "#9d5fcc", "#2a93a1", "#e8e9ec",
            ],
            chrome: ThemeChrome(
                accent: "#c46a1c", accent2: "#2f6fb8",
                sidebarBackground: "#eeeeeb", panelBackground: "#f2f2ef",
                border: "#00000014", text: "#2b2f36", secondaryText: "#6f7580",
                success: "#3f8a2e", warning: "#9a6b00", danger: "#c43d3d"
            )
        ),
        // 1. Terminalus Neon — the signature default look.
        Theme(
            id: "terminalus-neon", name: "Terminalus Neon",
            foreground: "#bff8ff", background: "#0b0816",
            cursor: "#ff2e97", cursorText: "#0b0816",
            selection: "#b026ff4d", selectionText: "#ffffff",
            link: "#00f0ff",
            ansi: [
                "#1b1530", "#ff2e63", "#39ff14", "#fcee0c", "#2d6bff", "#f000ff", "#00f0ff", "#d8d4f2",
                "#4b3f72", "#ff5c8d", "#7bff5c", "#fff45c", "#5c8cff", "#ff5cf5", "#5cf7ff", "#ffffff",
            ],
            chrome: ThemeChrome(
                accent: "#ff2e97", accent2: "#00f0ff",
                sidebarBackground: "#110c22", panelBackground: "#17112d",
                border: "#ff2e9740", text: "#e2fbff", secondaryText: "#8b82b8",
                glow: "#00f0ff",
                gradient: ["#ff2e97", "#b026ff", "#00f0ff", "#2d6bff"],
                success: "#39ff14", warning: "#fcee0c", danger: "#ff2e63"
            )
        ),

        // 2. Cyberpunk Neon (Roboron3042/Cyberpunk-Neon).
        Theme(
            id: "cyberpunk-neon", name: "Cyberpunk Neon",
            foreground: "#0abdc6", background: "#000b1e",
            cursor: "#0abdc6", cursorText: "#000b1e",
            selection: "#133e7c",
            link: "#ea00d9",
            ansi: [
                "#123e7c", "#ff0000", "#d300c4", "#f57800", "#123e7c", "#711c91", "#0abdc6", "#d7d7d5",
                "#1c61c2", "#ff0000", "#d300c4", "#f57800", "#00ff00", "#711c91", "#0abdc6", "#d7d7d5",
            ],
            chrome: ThemeChrome(
                accent: "#ea00d9", accent2: "#0abdc6",
                sidebarBackground: "#091833", panelBackground: "#0c2045",
                border: "#ea00d940", text: "#d7d7d5", secondaryText: "#4f7fbf",
                glow: "#ea00d9",
                gradient: ["#ea00d9", "#711c91", "#133e7c", "#0abdc6"],
                success: "#00ff00", warning: "#f57800", danger: "#ff0000"
            )
        ),

        // 3. SynthWave '84 (robb0wen/synthwave-vscode).
        Theme(
            id: "synthwave-84", name: "Synthwave '84",
            foreground: "#f0eff1", background: "#262335",
            cursor: "#f97e72", cursorText: "#262335",
            selection: "#ff7edb33",
            link: "#36f9f6",
            ansi: [
                "#171520", "#fe4450", "#72f1b8", "#fede5d", "#03edf9", "#ff7edb", "#36f9f6", "#f0eff1",
                "#614d85", "#f97e72", "#72f1b8", "#fede5d", "#2ee2fa", "#ff7edb", "#36f9f6", "#ffffff",
            ],
            chrome: ThemeChrome(
                accent: "#ff7edb", accent2: "#36f9f6",
                sidebarBackground: "#241b2f", panelBackground: "#2a2139",
                border: "#ff7edb40", text: "#f0eff1", secondaryText: "#848bbd",
                glow: "#ff7edb",
                gradient: ["#ff7edb", "#b467f5", "#36f9f6"],
                success: "#72f1b8", warning: "#fede5d", danger: "#fe4450"
            )
        ),

        // 4. Dracula.
        Theme(
            id: "dracula", name: "Dracula",
            foreground: "#f8f8f2", background: "#282a36",
            cursor: "#f8f8f2", cursorText: "#282a36",
            selection: "#44475a",
            ansi: [
                "#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
                "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff", "#ffffff",
            ],
            chrome: ThemeChrome(accent: "#bd93f9", accent2: "#ff79c6")
        ),

        // 5. Nord.
        Theme(
            id: "nord", name: "Nord",
            foreground: "#d8dee9", background: "#2e3440",
            cursor: "#d8dee9", cursorText: "#2e3440",
            selection: "#434c5e",
            ansi: [
                "#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
                "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4",
            ],
            chrome: ThemeChrome(accent: "#88c0d0", accent2: "#81a1c1")
        ),

        // 6. Tokyo Night (night).
        Theme(
            id: "tokyo-night", name: "Tokyo Night",
            foreground: "#c0caf5", background: "#1a1b26",
            cursor: "#c0caf5", cursorText: "#1a1b26",
            selection: "#283457", selectionText: "#c0caf5",
            ansi: [
                "#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
                "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5",
            ],
            chrome: ThemeChrome(accent: "#7aa2f7", accent2: "#bb9af7")
        ),

        // 7. Tokyo Night Storm.
        Theme(
            id: "tokyo-night-storm", name: "Tokyo Night Storm",
            foreground: "#c0caf5", background: "#24283b",
            cursor: "#c0caf5", cursorText: "#24283b",
            selection: "#2e3c64", selectionText: "#c0caf5",
            ansi: [
                "#1d202f", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
                "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5",
            ],
            chrome: ThemeChrome(accent: "#7aa2f7", accent2: "#bb9af7")
        ),

        // 8. Catppuccin Mocha.
        Theme(
            id: "catppuccin-mocha", name: "Catppuccin Mocha",
            foreground: "#cdd6f4", background: "#1e1e2e",
            cursor: "#f5e0dc", cursorText: "#1e1e2e",
            selection: "#585b70", selectionText: "#cdd6f4",
            ansi: [
                "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
                "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8",
            ],
            chrome: ThemeChrome(accent: "#cba6f7", accent2: "#f5c2e7")
        ),

        // 9. Catppuccin Macchiato.
        Theme(
            id: "catppuccin-macchiato", name: "Catppuccin Macchiato",
            foreground: "#cad3f5", background: "#24273a",
            cursor: "#f4dbd6", cursorText: "#24273a",
            selection: "#5b6078", selectionText: "#cad3f5",
            ansi: [
                "#494d64", "#ed8796", "#a6da95", "#eed49f", "#8aadf4", "#f5bde6", "#8bd5ca", "#b8c0e0",
                "#5b6078", "#ed8796", "#a6da95", "#eed49f", "#8aadf4", "#f5bde6", "#8bd5ca", "#a5adcb",
            ],
            chrome: ThemeChrome(accent: "#c6a0f6", accent2: "#f5bde6")
        ),

        // 10. Catppuccin Frappé.
        Theme(
            id: "catppuccin-frappe", name: "Catppuccin Frappé",
            foreground: "#c6d0f5", background: "#303446",
            cursor: "#f2d5cf", cursorText: "#303446",
            selection: "#626880", selectionText: "#c6d0f5",
            ansi: [
                "#51576d", "#e78284", "#a6d189", "#e5c890", "#8caaee", "#f4b8e4", "#81c8be", "#b5bfe2",
                "#626880", "#e78284", "#a6d189", "#e5c890", "#8caaee", "#f4b8e4", "#81c8be", "#a5adce",
            ],
            chrome: ThemeChrome(accent: "#ca9ee6", accent2: "#f4b8e4")
        ),

        // 11. Catppuccin Latte (light).
        Theme(
            id: "catppuccin-latte", name: "Catppuccin Latte",
            foreground: "#4c4f69", background: "#eff1f5",
            cursor: "#dc8a78", cursorText: "#eff1f5",
            selection: "#acb0be", selectionText: "#4c4f69",
            ansi: [
                "#5c5f77", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#acb0be",
                "#6c6f85", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#bcc0cc",
            ],
            chrome: ThemeChrome(accent: "#8839ef", accent2: "#ea76cb")
        ),

        // 12. Gruvbox Dark.
        Theme(
            id: "gruvbox-dark", name: "Gruvbox Dark",
            foreground: "#ebdbb2", background: "#282828",
            cursor: "#ebdbb2", cursorText: "#282828",
            selection: "#504945", selectionText: "#ebdbb2",
            ansi: [
                "#282828", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#a89984",
                "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2",
            ],
            chrome: ThemeChrome(accent: "#fe8019", accent2: "#fabd2f")
        ),

        // 13. Gruvbox Light.
        Theme(
            id: "gruvbox-light", name: "Gruvbox Light",
            foreground: "#3c3836", background: "#fbf1c7",
            cursor: "#3c3836", cursorText: "#fbf1c7",
            selection: "#d5c4a1", selectionText: "#3c3836",
            ansi: [
                "#fbf1c7", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#7c6f64",
                "#928374", "#9d0006", "#79740e", "#b57614", "#076678", "#8f3f71", "#427b58", "#3c3836",
            ],
            chrome: ThemeChrome(accent: "#af3a03", accent2: "#b57614")
        ),

        // 14. Solarized Dark.
        Theme(
            id: "solarized-dark", name: "Solarized Dark",
            foreground: "#839496", background: "#002b36",
            cursor: "#93a1a1", cursorText: "#002b36",
            selection: "#073642", selectionText: "#93a1a1",
            ansi: [
                "#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3",
            ],
            chrome: ThemeChrome(accent: "#268bd2", accent2: "#2aa198")
        ),

        // 15. Solarized Light.
        Theme(
            id: "solarized-light", name: "Solarized Light",
            foreground: "#657b83", background: "#fdf6e3",
            cursor: "#586e75", cursorText: "#fdf6e3",
            selection: "#268bd233", selectionText: "#586e75",
            ansi: [
                "#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3",
            ],
            chrome: ThemeChrome(accent: "#268bd2", accent2: "#2aa198")
        ),

        // 16. One Dark (Atom).
        Theme(
            id: "one-dark", name: "One Dark",
            foreground: "#abb2bf", background: "#282c34",
            cursor: "#528bff", cursorText: "#282c34",
            selection: "#3e4451", selectionText: "#abb2bf",
            ansi: [
                "#1e2127", "#e06c75", "#98c379", "#d19a66", "#61afef", "#c678dd", "#56b6c2", "#abb2bf",
                "#5c6370", "#e06c75", "#98c379", "#d19a66", "#61afef", "#c678dd", "#56b6c2", "#ffffff",
            ],
            chrome: ThemeChrome(accent: "#61afef", accent2: "#c678dd")
        ),

        // 17. One Light (Atom).
        Theme(
            id: "one-light", name: "One Light",
            foreground: "#383a42", background: "#fafafa",
            cursor: "#526fff", cursorText: "#fafafa",
            selection: "#526fff33", selectionText: "#383a42",
            ansi: [
                "#383a42", "#e45649", "#50a14f", "#c18401", "#4078f2", "#a626a4", "#0184bc", "#a0a1a7",
                "#4f525e", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#ffffff",
            ],
            chrome: ThemeChrome(accent: "#4078f2", accent2: "#a626a4")
        ),

        // 18. Monokai.
        Theme(
            id: "monokai", name: "Monokai",
            foreground: "#f8f8f2", background: "#272822",
            cursor: "#f8f8f0", cursorText: "#272822",
            selection: "#49483e", selectionText: "#f8f8f2",
            ansi: [
                "#272822", "#f92672", "#a6e22e", "#e6db74", "#66d9ef", "#ae81ff", "#a1efe4", "#f8f8f2",
                "#75715e", "#f92672", "#a6e22e", "#e6db74", "#66d9ef", "#ae81ff", "#a1efe4", "#f9f8f5",
            ],
            chrome: ThemeChrome(accent: "#f92672", accent2: "#a6e22e")
        ),

        // 19. Rosé Pine.
        Theme(
            id: "rose-pine", name: "Rosé Pine",
            foreground: "#e0def4", background: "#191724",
            cursor: "#524f67", cursorText: "#e0def4",
            selection: "#403d52", selectionText: "#e0def4",
            ansi: [
                "#26233a", "#eb6f92", "#31748f", "#f6c177", "#9ccfd8", "#c4a7e7", "#ebbcba", "#e0def4",
                "#6e6a86", "#eb6f92", "#31748f", "#f6c177", "#9ccfd8", "#c4a7e7", "#ebbcba", "#e0def4",
            ],
            chrome: ThemeChrome(accent: "#ebbcba", accent2: "#c4a7e7")
        ),

        // 20. Rosé Pine Moon.
        Theme(
            id: "rose-pine-moon", name: "Rosé Pine Moon",
            foreground: "#e0def4", background: "#232136",
            cursor: "#56526e", cursorText: "#e0def4",
            selection: "#44415a", selectionText: "#e0def4",
            ansi: [
                "#393552", "#eb6f92", "#3e8fb0", "#f6c177", "#9ccfd8", "#c4a7e7", "#ea9a97", "#e0def4",
                "#6e6a86", "#eb6f92", "#3e8fb0", "#f6c177", "#9ccfd8", "#c4a7e7", "#ea9a97", "#e0def4",
            ],
            chrome: ThemeChrome(accent: "#ea9a97", accent2: "#c4a7e7")
        ),

        // 21. Rosé Pine Dawn (light).
        Theme(
            id: "rose-pine-dawn", name: "Rosé Pine Dawn",
            foreground: "#575279", background: "#faf4ed",
            cursor: "#cecacd", cursorText: "#575279",
            selection: "#dfdad9", selectionText: "#575279",
            ansi: [
                "#f2e9e1", "#b4637a", "#286983", "#ea9d34", "#56949f", "#907aa9", "#d7827e", "#575279",
                "#9893a5", "#b4637a", "#286983", "#ea9d34", "#56949f", "#907aa9", "#d7827e", "#575279",
            ],
            chrome: ThemeChrome(accent: "#d7827e", accent2: "#907aa9")
        ),

        // 22. Everforest Dark (medium).
        Theme(
            id: "everforest-dark", name: "Everforest Dark",
            foreground: "#d3c6aa", background: "#2d353b",
            cursor: "#d3c6aa", cursorText: "#2d353b",
            selection: "#543a48", selectionText: "#d3c6aa",
            ansi: [
                "#475258", "#e67e80", "#a7c080", "#dbbc7f", "#7fbbb3", "#d699b6", "#83c092", "#d3c6aa",
                "#859289", "#e67e80", "#a7c080", "#dbbc7f", "#7fbbb3", "#d699b6", "#83c092", "#d3c6aa",
            ],
            chrome: ThemeChrome(accent: "#a7c080", accent2: "#83c092")
        ),

        // 23. Kanagawa Wave.
        Theme(
            id: "kanagawa-wave", name: "Kanagawa Wave",
            foreground: "#dcd7ba", background: "#1f1f28",
            cursor: "#c8c093", cursorText: "#1f1f28",
            selection: "#2d4f67", selectionText: "#c8c093",
            ansi: [
                "#090618", "#c34043", "#76946a", "#c0a36e", "#7e9cd8", "#957fb8", "#6a9589", "#c8c093",
                "#727169", "#e82424", "#98bb6c", "#e6c384", "#7fb4ca", "#938aa9", "#7aa89f", "#dcd7ba",
            ],
            chrome: ThemeChrome(accent: "#7e9cd8", accent2: "#957fb8")
        ),

        // 24. Matrix — phosphor green on black.
        Theme(
            id: "matrix", name: "Matrix",
            foreground: "#00ff41", background: "#030a05",
            cursor: "#00ff41", cursorText: "#030a05",
            selection: "#00ff4133", selectionText: "#d4ffdc",
            link: "#5cffc8",
            ansi: [
                "#0b1f10", "#c96a3c", "#00c832", "#b8d83a", "#1f9e5c", "#4fb87a", "#2fd6a0", "#8cf5a8",
                "#2e5c37", "#f08c5a", "#00ff41", "#e2ff5c", "#3fd67f", "#7fe8a0", "#5cffc8", "#d4ffdc",
            ],
            chrome: ThemeChrome(
                accent: "#00ff41", accent2: "#7dffa0",
                sidebarBackground: "#041008", panelBackground: "#07170c",
                border: "#00ff4140", text: "#b8ffc8", secondaryText: "#3f8f52",
                glow: "#00ff41",
                gradient: ["#003b00", "#008f11", "#00ff41", "#7dffa0"],
                success: "#00ff41", warning: "#e2ff5c", danger: "#f08c5a"
            )
        ),

        // 25. Retro Amber CRT.
        Theme(
            id: "retro-amber", name: "Retro Amber CRT",
            foreground: "#ffb000", background: "#1a1000",
            cursor: "#ffcc00", cursorText: "#1a1000",
            selection: "#ffb00040", selectionText: "#fff4e0",
            link: "#ffe066",
            ansi: [
                "#2b1c00", "#ff5f1f", "#d9b300", "#ffc233", "#b37700", "#ff8c42", "#ffcf73", "#ffd9a0",
                "#6b4a00", "#ff8040", "#ffd23f", "#ffe066", "#d99a26", "#ffa866", "#ffe3a3", "#fff4e0",
            ],
            chrome: ThemeChrome(
                accent: "#ffb000", accent2: "#ffcc66",
                sidebarBackground: "#140c00", panelBackground: "#221500",
                border: "#ffb00040", text: "#ffb000", secondaryText: "#a67200",
                glow: "#ffb000",
                gradient: ["#ff7a00", "#ffb000", "#ffd966"],
                success: "#ffd23f", warning: "#ffb000", danger: "#ff5f1f"
            )
        ),

        // 26. Retro Green CRT.
        Theme(
            id: "retro-green", name: "Retro Green CRT",
            foreground: "#33ff33", background: "#001100",
            cursor: "#66ff66", cursorText: "#001100",
            selection: "#33ff3340", selectionText: "#ccffcc",
            link: "#55ffcc",
            ansi: [
                "#0a260a", "#b8913a", "#22cc22", "#aadd33", "#1a9955", "#55bb77", "#33ccaa", "#99ee99",
                "#1f5c1f", "#d9ad4a", "#33ff33", "#ccff55", "#33cc77", "#77dd99", "#55ffcc", "#ccffcc",
            ],
            chrome: ThemeChrome(
                accent: "#33ff33", accent2: "#99ff66",
                sidebarBackground: "#000c00", panelBackground: "#001a00",
                border: "#33ff3340", text: "#33ff33", secondaryText: "#1f991f",
                glow: "#33ff33",
                gradient: ["#0f6f0f", "#1fbf1f", "#33ff33", "#99ff99"],
                success: "#33ff33", warning: "#ccff55", danger: "#d9ad4a"
            )
        ),

        // 27. GitHub Dark (Default).
        Theme(
            id: "github-dark", name: "GitHub Dark",
            foreground: "#e6edf3", background: "#0d1117",
            cursor: "#2f81f7", cursorText: "#0d1117",
            selection: "#264f78", selectionText: "#e6edf3",
            ansi: [
                "#484f58", "#ff7b72", "#3fb950", "#d29922", "#58a6ff", "#bc8cff", "#39c5cf", "#b1bac4",
                "#6e7681", "#ffa198", "#56d364", "#e3b341", "#79c0ff", "#d2a8ff", "#56d4dd", "#ffffff",
            ],
            chrome: ThemeChrome(accent: "#58a6ff", accent2: "#3fb950")
        ),

        // 28. Night Owl.
        Theme(
            id: "night-owl", name: "Night Owl",
            foreground: "#d6deeb", background: "#011627",
            cursor: "#80a4c2", cursorText: "#011627",
            selection: "#1d3b53", selectionText: "#d6deeb",
            ansi: [
                "#011627", "#ef5350", "#22da6e", "#addb67", "#82aaff", "#c792ea", "#21c7a8", "#ffffff",
                "#575656", "#ef5350", "#22da6e", "#ffeb95", "#82aaff", "#c792ea", "#7fdbca", "#ffffff",
            ],
            chrome: ThemeChrome(accent: "#82aaff", accent2: "#c792ea")
        ),
    ]

    /// The theme used when no preference has been saved.
    public static let defaultID = "graphite"

    /// Looks up a built-in theme by id.
    public static func builtin(id: String) -> Theme? { builtins.first { $0.id == id } }
}
