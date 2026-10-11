// Veil's small, pinned SwiftTerm host extension. Copied by prepare-native-engine.mjs.
#if os(macOS)
import AppKit

extension TerminalView.FontSet {
    init(veilNormal: NSFont, bold: NSFont, useBold: Bool) {
        normal = veilNormal
        self.bold = useBold ? bold : veilNormal
        italic = NSFontManager.shared.convert(veilNormal, toHaveTrait: .italicFontMask)
        boldItalic = NSFontManager.shared.convert(useBold ? bold : veilNormal, toHaveTrait: .italicFontMask)
    }
}

extension TerminalView {
    /// Observe only user input, synchronously before PTY delivery, from any sending thread.
    /// The callback must be fast, thread-safe, and must not recursively send terminal input.
    public nonisolated func setVeilInputObserver(_ observer: (@Sendable ([UInt8]) -> Void)?) {
        inputSender.setVeilObserver(observer)
    }

    /// Apply host appearance once per config change, never on the input/output path.
    public func applyVeilAppearance(normalFont: NSFont, boldFont: NSFont, useBold: Bool,
                                    boldForeground: NSColor, ansiColors: Bool,
                                    allowBlink: Bool, dynamicForeground: Bool, brightBold: Bool) {
        fontSet = FontSet(veilNormal: normalFont, bold: boldFont, useBold: useBold)
        veilBoldForeground = boldForeground
        veilAllowBlink = allowBlink
        useBrightColors = brightBold
        withTerminal { terminal in
            if terminal.veilAnsiColors != ansiColors || terminal.veilAllowBlink != allowBlink {
                terminal.veilResetAttributes()
            }
            terminal.veilAnsiColors = ansiColors
            terminal.veilAllowBlink = allowBlink
            terminal.veilDynamicForeground = dynamicForeground
            terminal.veilDefaultForeground = nativeForegroundColor.getTerminalColor()
            terminal.updateFullScreen()
        }
        resetFont()
        colorsChanged()
        updateTextBlinkLifecycle()
        frameDriver.markDirty()
    }
}
#endif
