import AppKit
import CoreText
import VeilCore

enum Resources {
    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static var bin: URL {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("bin")
        if let bundled, FileManager.default.fileExists(atPath: bundled.appendingPathComponent("veil").path) { return bundled }
        return repository.appendingPathComponent("bin")
    }
    static var pip: URL {
        let bundled = bin.appendingPathComponent("veil-pip")
        return FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : repository.appendingPathComponent("native/build/veil-pip")
    }
    static func registerFonts() {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Fonts")
        let folders = bundled.map { [$0] } ?? [repository.appendingPathComponent("assets/Fonts")]
        for folder in folders {
            for url in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "ttf" {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

func veilColor(_ hex: String, fallback: NSColor = .white) -> NSColor {
    let raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard [6, 8].contains(raw.count), let value = UInt64(raw, radix: 16) else { return fallback }
    let rgb = raw.count == 8 ? value >> 8 : value
    return NSColor(srgbRed: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255,
                   blue: Double(rgb & 255) / 255, alpha: raw.count == 8 ? Double(value & 255) / 255 : 1)
}

@MainActor
func veilFont(_ config: Configuration, bold: Bool = false) -> NSFont {
    let size = max(6, min(72, config.number("font-size", default: 14)))
    let weightKey = bold ? "font-bold-weight" : "font-weight"
    let rawWeight = config.string(weightKey, default: "")
    let weight = rawWeight == "normal" ? 400 : rawWeight == "bold" ? 700 : config.number(weightKey, default: bold ? 700 : 450)
    let families = config.string("font-family", default: "JetBrains Mono, SFMono-Regular, Menlo, monospace")
        .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    let base = families.compactMap { NSFont(name: $0, size: size) }.first ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    // Preserve exact variable-font weight where available, including Veil's 450.
    let ct = base as CTFont
    if let axes = CTFontCopyVariationAxes(ct) as? [[CFString: Any]],
       let axis = axes.first(where: { ($0[kCTFontVariationAxisIdentifierKey] as? NSNumber)?.uint32Value == 0x77676874 }),
       let key = axis[kCTFontVariationAxisIdentifierKey] as? NSNumber {
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontVariationAttribute: [key: weight]] as CFDictionary)
        return CTFontCreateCopyWithAttributes(ct, size, nil, descriptor) as NSFont
    }
    return weight >= 600 ? NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask) : base
}

@MainActor
final class GlassBackground: NSView {
    private var tint = NSColor.clear
    private let fallback = NSVisualEffectView()
    private var radius = 0
    private static let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)
    override init(frame: NSRect) {
        super.init(frame: frame)
        fallback.blendingMode = .behindWindow
        fallback.material = .underWindowBackground
        fallback.state = .active
        fallback.isHidden = true
        fallback.autoresizingMask = [.width, .height]
        addSubview(fallback)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { tint.setFill(); dirtyRect.fill(using: .sourceOver) }
    func apply(_ config: Configuration, window: NSWindow) {
        let transparent = config.bool("transparent", default: true)
        let clear = config.string("glass-mode", default: "liquid") == "clear" || config.bool("clear-mode", default: false)
        let opacity = transparent ? max(0, min(1, config.number("glass-opacity", default: 0))) : 1
        tint = veilColor(config.string("glass-color", default: "#14171c")).withAlphaComponent(opacity)
        radius = transparent && !clear ? Int(max(0, min(100, config.number("glass-blur", default: 28)))) : 0
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = !(clear && opacity == 0)
        var applied = false
        if let library = Self.library, let connection = dlsym(library, "CGSMainConnectionID"),
           let blur = dlsym(library, "CGSSetWindowBackgroundBlurRadius") {
            let get = unsafeBitCast(connection, to: (@convention(c) () -> Int32).self)
            let set = unsafeBitCast(blur, to: (@convention(c) (Int32, UInt32, Int32) -> Int32).self)
            applied = set(get(), UInt32(window.windowNumber), Int32(radius)) == 0
        }
        fallback.frame = bounds
        fallback.isHidden = applied || radius == 0
        needsDisplay = true
    }
}
