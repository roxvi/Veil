import AppKit
import Foundation
import Testing
@testable import SwiftTerm

private final class ParserDelegate: TerminalDelegate {
    var replies: [[UInt8]] = []
    func showCursor(source: Terminal) {}
    func hideCursor(source: Terminal) {}
    func setTerminalTitle(source: Terminal, title: String) {}
    func setTerminalIconTitle(source: Terminal, title: String) {}
    func windowCommand(source: Terminal, command: Terminal.WindowManipulationCommand) -> [UInt8]? { nil }
    func sizeChanged(source: Terminal) {}
    func send(source: Terminal, data: ArraySlice<UInt8>) { replies.append(Array(data)) }
}

@Suite("Veil pinned engine appearance")
struct AppearanceTests {
    @Test func disabledANSIRestoresDefaultAttributesWithoutDroppingText() {
        let delegate = ParserDelegate()
        // Keep the delegate alive for the entire parser lifetime.
        let engine = Terminal(delegate: delegate)
        engine.terminalLock.withLock {
            engine.feed(text: "\u{1b}[1;31m")
            #expect(engine.currentAttribute.style.contains(.bold))
            engine.veilAnsiColors = false
            engine.feed(text: "\u{1b}[38;2;1;2;3;48;5;196mX")
            #expect(engine.currentAttribute == CharData.defaultAttr)
            #expect(engine.buffer.x == 1)
            engine.veilAnsiColors = true
            engine.feed(text: "\u{1b}[32m")
            #expect(engine.currentAttribute.fg == .ansi256(code: 2))
        }
    }

    @Test func explicitIndexedBrightAndTruecolorSurviveParser() {
        let delegate = ParserDelegate()
        let terminal = Terminal(delegate: delegate)
        terminal.terminalLock.withLock {
            terminal.feed(text: "\u{1b}[38;5;196m")
            #expect(terminal.currentAttribute.fg == .ansi256(code: 196))
            terminal.feed(text: "\u{1b}[90m")
            #expect(terminal.currentAttribute.fg == .ansi256(code: 8))
            #expect(!terminal.currentAttribute.style.contains(.bold))
            terminal.feed(text: "\u{1b}[38;2;17;34;51m")
            #expect(terminal.currentAttribute.fg == .trueColor(red: 17, green: 34, blue: 51))
        }
    }

    @Test func blinkDisabledKeepsMixedSGRAndIndexedColor() {
        let delegate = ParserDelegate()
        let terminal = Terminal(delegate: delegate)
        terminal.terminalLock.withLock {
            terminal.veilAllowBlink = false
            terminal.feed(text: "\u{1b}[1;5;31m")
            #expect(terminal.currentAttribute.style.contains(.bold))
            #expect(!terminal.currentAttribute.style.contains(.blink))
            #expect(terminal.currentAttribute.fg == .ansi256(code: 1))
            terminal.feed(text: "\u{1b}[38;5;196m")
            #expect(terminal.currentAttribute.fg == .ansi256(code: 196))
            terminal.veilAllowBlink = true
            terminal.feed(text: "\u{1b}[5m")
            #expect(terminal.currentAttribute.style.contains(.blink))
        }
    }

    @Test func resettingAppearanceDoesNotCorruptPartialEscape() {
        let delegate = ParserDelegate()
        let terminal = Terminal(delegate: delegate)
        terminal.terminalLock.withLock {
            terminal.feed(text: "\u{1b}[38;2;17;")
            terminal.veilResetAttributes()
            terminal.feed(text: "34;51m")
            #expect(terminal.currentAttribute.fg == .trueColor(red: 17, green: 34, blue: 51))
        }
    }

    @Test func foregroundMutationQueriesAndResetRespectPolicy() {
        let delegate = ParserDelegate()
        let terminal = Terminal(delegate: delegate)
        let original = Color(red: 0x1111, green: 0x2222, blue: 0x3333)
        terminal.terminalLock.withLock {
            terminal.foregroundColor = original; terminal.veilDefaultForeground = original
            terminal.feed(text: "\u{1b}]10;#abcdef\u{7}")
            let changed = terminal.foregroundColor
            #expect(changed != original)
            terminal.veilDynamicForeground = false
            terminal.feed(text: "\u{1b}]10;#ffffff\u{7}\u{1b}]110\u{7}")
            #expect(terminal.foregroundColor == changed)
            terminal.feed(text: "\u{1b}]10;?\u{7}")
            #expect(!delegate.replies.isEmpty)
            #expect(String(decoding: delegate.replies.flatMap { $0 }, as: UTF8.self).contains("10;rgb:"))
            terminal.veilDynamicForeground = true
            terminal.feed(text: "\u{1b}]110\u{7}")
            #expect(terminal.foregroundColor == original)
        }
    }

    @Test @MainActor func snapshotColorsPreserveExplicitIndicesWhenBrightBoldIsOff() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        view.useBrightColors = false
        let palette = view.withTerminal { $0.ansiColors }
        let context = SnapshotRenderContext(viewState: FrameViewState(view: view), style: .empty, ansiColors: palette, cols: 80)
        for index: UInt8 in [8, 15, 196, 255] {
            let actual = SwiftTerm.mapColor(color: .ansi256(code: index), isFg: true, isBold: true, context: context)
            #expect(actual.getTerminalColor() == palette[Int(index)])
        }
        let actual = SwiftTerm.mapColor(color: .trueColor(red: 17, green: 34, blue: 51), isFg: true, isBold: false, context: context)
        #expect(actual.getTerminalColor() == Color(red: 0x1111, green: 0x2222, blue: 0x3333))
    }

    @Test @MainActor func brightBoldPromotesOnlyNormalForeground() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        view.useBrightColors = true
        let palette = view.withTerminal { $0.ansiColors }
        let context = SnapshotRenderContext(viewState: FrameViewState(view: view), style: .empty, ansiColors: palette, cols: 80)
        #expect(SwiftTerm.mapColor(color: .ansi256(code: 7), isFg: true, isBold: true, context: context).getTerminalColor() == palette[15])
        #expect(SwiftTerm.mapColor(color: .ansi256(code: 7), isFg: false, isBold: true, context: context).getTerminalColor() == palette[7])
        #expect(SwiftTerm.mapColor(color: .ansi256(code: 196), isFg: true, isBold: true, context: context).getTerminalColor() == palette[196])
    }

    @Test @MainActor func userInputObserverRunsBeforeDeliveryAndCanBeRemoved() {
        let events = Locked<[String]>([])
        let sender = TerminalInputSender()
        sender.setVeilObserver { bytes in events.withLock { $0.append("observe:" + String(decoding: bytes, as: UTF8.self)) } }
        sender.replaceDelivery { bytes in events.withLock { $0.append("deliver:" + String(decoding: bytes, as: UTF8.self)) } }
        sender.send(data: Array("abc".utf8)[...])
        #expect(events.withLock { $0 } == ["observe:abc", "deliver:abc"])
        sender.setVeilObserver(nil)
        sender.send(data: Array("d".utf8)[...])
        #expect(events.withLock { $0 } == ["observe:abc", "deliver:abc", "deliver:d"])
    }

    @Test @MainActor func parserQueriesDoNotLookLikeUserTyping() {
        let observed = Locked<[UInt8]>([])
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        view.setVeilInputObserver { bytes in observed.withLock { $0 += bytes } }
        view.withTerminal { $0.feed(text: "\u{1b}[6n\u{1b}]10;?\u{7}") }
        #expect(observed.withLock { $0 }.isEmpty)
        view.send(txt: "typed")
        #expect(String(decoding: observed.withLock { $0 }, as: UTF8.self) == "typed")
    }
}
