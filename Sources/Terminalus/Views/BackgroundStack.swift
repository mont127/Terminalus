import AppKit
import SwiftUI
import TerminalusCore

/// Everything painted behind the (transparent) terminals: the themed tint, an optional image and
/// the animated gradient. The window-level blur sits below this.
struct BackgroundStack: View {
    let theme: ResolvedTheme
    let window: WindowSettings
    let background: BackgroundSettings
    let effectsEnabled: Bool
    let paused: Bool

    var body: some View {
        ZStack {
            theme.background.withAlpha(window.backgroundOpacity).color
            if !background.image.path.isEmpty, let img = BackgroundImageCache.image(background.image.path) {
                BackgroundImageView(image: img, settings: background.image)
            }
            if background.gradient.enabled && effectsEnabled {
                let custom = background.gradient.colors.compactMap(RGBA.init(hex:))
                GradientLayerRepresentable(config: GradientLayerView.Config(
                    style: background.gradient.style,
                    colors: custom.count >= 2 ? custom : theme.gradient,
                    speed: background.gradient.speed,
                    animated: background.gradient.animated,
                    paused: paused
                ))
                .opacity(background.gradient.opacity)
                .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }
}

enum BackgroundImageCache {
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor
    static func image(_ path: String) -> NSImage? {
        let p = (path as NSString).expandingTildeInPath
        if let img = cache[p] { return img }
        guard let img = NSImage(contentsOfFile: p) else { return nil }
        cache[p] = img
        return img
    }
}

private struct BackgroundImageView: View {
    let image: NSImage
    let settings: BackgroundImageSettings

    var body: some View {
        GeometryReader { geo in
            Group {
                switch settings.mode {
                case .fill:
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                case .fit:
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                case .stretch:
                    Image(nsImage: image).resizable()
                case .tile:
                    Image(nsImage: image).resizable(resizingMode: .tile)
                case .center:
                    Image(nsImage: image).frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .saturation(settings.saturation)
            .blur(radius: settings.blur)
            .opacity(settings.opacity)
        }
    }
}
