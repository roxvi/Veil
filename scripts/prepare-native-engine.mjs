// Exact-revision, reproducible engine overlay. Never edits application source or user config.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const checkout = path.join(root, 'macOS/.build/checkouts/SwiftTerm');
const revision = '4dcf5278fde40af60c36f667d8a472a90b38b247';
const git = (...args) => execFileSync('git', ['-C', checkout, ...args], {encoding:'utf8'}).trimEnd();
if (git('rev-parse', 'HEAD') !== revision) throw new Error('Unreviewed SwiftTerm revision; refusing engine overlay.');
const edits = new Map();
function patch(file, before, after, count = 1) {
  const key = `Sources/SwiftTerm/${file}`;
  const source = edits.get(key) ?? execFileSync('git', ['-C', checkout, 'show', `${revision}:${key}`], {encoding:'utf8'});
  const found = source.split(before).length - 1;
  if (found !== count) throw new Error(`${file}: expected ${count} exact anchors, found ${found}`);
  edits.set(key, source.split(before).join(after));
}
patch('Mac/MacTerminalView.swift', '    var fontSet: FontSet\n', '    var fontSet: FontSet\n    var veilBoldForeground: NSColor?\n    var veilAllowBlink = true\n');
patch('Apple/AppleTerminalView.swift', 'public final class TerminalInputSender: Sendable {\n', `public final class TerminalInputSender: Sendable {
    private let veilObserver = Locked<(@Sendable ([UInt8]) -> Void)?>(nil)
    func setVeilObserver(_ observer: (@Sendable ([UInt8]) -> Void)?) {
        veilObserver.withLock { $0 = observer }
    }
`);
patch('Apple/AppleTerminalView.swift', '        handlers.register?(bytes)\n', '        veilObserver.withLock { $0 }?(bytes)\n        handlers.register?(bytes)\n');
patch('Terminal.swift', 'open class Terminal {\n', `open class Terminal {
    var veilAnsiColors = true
    var veilAllowBlink = true
    var veilDynamicForeground = true
    var veilDefaultForeground = Color.defaultForeground
    func veilResetAttributes() { setCurrentAttribute(CharData.defaultAttr) }
`);
patch('Terminal.swift', '    private func cmdCharAttributes(_ pars: CsiParameters) {\n', '    private func cmdCharAttributes(_ pars: CsiParameters) {\n        guard veilAnsiColors else { setCurrentAttribute(CharData.defaultAttr); return }\n');
patch('Terminal.swift', '                // blink\n                style = [style, .blink]', '                // Preserve the remaining SGR attributes when blinking is disabled.\n                if veilAllowBlink { style = [style, .blink] }');
patch('Terminal.swift', '            case 0:\n                foregroundColor = color', '            case 0:\n                guard veilDynamicForeground else { continue }\n                foregroundColor = color');
patch('EscapeSequenceParser.swift', '        case 112:  terminal.tdel?.setCursorColor(source: terminal, color: nil)', `        case 110:
            if terminal.veilDynamicForeground {
                terminal.foregroundColor = terminal.veilDefaultForeground
                terminal.tdel?.setForegroundColor(source: terminal, color: terminal.veilDefaultForeground)
            }
        case 112:  terminal.tdel?.setCursorColor(source: terminal, color: nil)`);
patch('Apple/AppleTerminalView.swift', '    let useBrightColors: Bool\n    let minimumContrastRatio: CGFloat', '    let useBrightColors: Bool\n    let veilBoldForeground: FrameColor?\n    let minimumContrastRatio: CGFloat', 2);
patch('Apple/AppleTerminalView.swift', '        useBrightColors = view.useBrightColors', '        useBrightColors = view.useBrightColors\n        veilBoldForeground = view.veilBoldForeground.map { FrameColor($0, view: view) }');
patch('Apple/AppleTerminalView.swift', '        useBrightColors = viewState.useBrightColors', '        useBrightColors = viewState.useBrightColors\n        veilBoldForeground = viewState.veilBoldForeground');
patch('Apple/AppleTerminalView.swift', '        identityHasher.combine(useBrightColors)', '        identityHasher.combine(useBrightColors)\n        identityHasher.combine(veilBoldForeground)');
patch('Apple/AppleTerminalView.swift', '        let canBlink = window != nil && textBlinkApplicationActive', '        let canBlink = veilAllowBlink && window != nil && textBlinkApplicationActive');
patch('Apple/AppleTerminalView.swift', '                return effectiveNativeForegroundColor\n            } else {', '                return isBold ? (veilBoldForeground ?? effectiveNativeForegroundColor) : effectiveNativeForegroundColor\n            } else {');
patch('Apple/AppleTerminalView.swift', '            if useBrightColors {\n                midx = ansi < 7 ? (Int (ansi) + (isBold ? 8 : 0)) : Int (ansi)\n            } else {\n                midx = ansi > 7 ? (Int (ansi) - 8) : Int(ansi)\n            }', '            midx = Int(ansi) + (isFg && isBold && useBrightColors && ansi < 8 ? 8 : 0)');
patch('Apple/AppleTerminalView.swift', '        if case .ansi256(let code) = fg, code > 7, !useBrightColors {\n            useBoldForBrightColor = true\n        }', '        // Explicit bright/indexed colors never implicitly change font weight.');
patch('Apple/SnapshotTextBuilder.swift', '            brightNeedsBold = code > 7 && !context.useBrightColors', '            brightNeedsBold = false // Explicit color indices do not imply bold.');
patch('Apple/SnapshotTextBuilder.swift', '    case .defaultColor:\n        return isFg ? context.effectiveForegroundColor : context.effectiveBackgroundColor', '    case .defaultColor:\n        return isFg ? (isBold ? (context.veilBoldForeground?.nativeColor ?? context.effectiveForegroundColor) : context.effectiveForegroundColor) : context.effectiveBackgroundColor');
patch('Apple/SnapshotTextBuilder.swift', '        if context.useBrightColors {\n            index = ansi < 7 ? Int(ansi) + (isBold ? 8 : 0) : Int(ansi)\n        } else {\n            index = ansi > 7 ? Int(ansi) - 8 : Int(ansi)\n        }', '        index = Int(ansi) + (isFg && isBold && context.useBrightColors && ansi < 8 ? 8 : 0)');

// Validate every anchor before writing anything. Outputs are regenerated from immutable Git
// objects, not repeatedly patched; a second invocation produces byte-identical files.
for (const [file, content] of edits) {
  const destination = path.join(checkout, file);
  if (fs.readFileSync(destination, 'utf8') !== content) {
    fs.chmodSync(destination, fs.statSync(destination).mode | 0o200);
    fs.writeFileSync(destination, content);
  }
}
fs.chmodSync(path.join(checkout, 'Sources/SwiftTerm/Mac'), 0o755);
const overlay = fs.readFileSync(path.join(root, 'macOS/EngineOverlay/VeilAppearance.swift'), 'utf8');
const overlayDestination = path.join(checkout, 'Sources/SwiftTerm/Mac/VeilAppearance.swift');
if (!fs.existsSync(overlayDestination) || fs.readFileSync(overlayDestination, 'utf8') !== overlay) fs.writeFileSync(overlayDestination, overlay);
console.log(`Prepared Veil appearance overlay against SwiftTerm ${revision}.`);
