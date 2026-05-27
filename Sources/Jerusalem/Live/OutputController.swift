import SwiftUI
import AppKit

/// A display available for audience output.
struct OutputScreen: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
}

/// Pure, testable rule for which screen drives the audience output.
enum ScreenSelection {
    /// Prefer any screen other than the main (menu-bar) screen; fall back to the
    /// only screen when there's a single display.
    static func outputIndex(screenCount: Int, mainIndex: Int) -> Int {
        guard screenCount > 1 else { return 0 }
        return (0..<screenCount).first { $0 != mainIndex } ?? 0
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Owns the audience output window and keeps it correct across display changes.
///
/// On an external display the window is borderless and covers the screen; with only
/// one display it opens as a resizable preview window so the operator UI isn't
/// hijacked during development. Reacts to `didChangeScreenParameters` so a
/// resolution change repositions the window and an unplugged display fails over to
/// a remaining screen instead of crashing.
@MainActor
@Observable
final class OutputController: NSObject {
    private(set) var isActive = false
    private(set) var activeScreenID: CGDirectDisplayID?
    private(set) var screens: [OutputScreen] = []

    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private let live: LiveState

    init(live: LiveState) {
        self.live = live
        super.init()
        refreshScreens()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    var activeScreenName: String {
        screens.first { $0.id == activeScreenID }?.name ?? "Output"
    }

    func refreshScreens() {
        screens = NSScreen.screens.map { OutputScreen(id: $0.displayID, name: $0.localizedName) }
    }

    func preferredScreen() -> NSScreen? {
        let all = NSScreen.screens
        guard !all.isEmpty else { return nil }
        let mainIndex = all.firstIndex { $0 == NSScreen.main } ?? 0
        return all[ScreenSelection.outputIndex(screenCount: all.count, mainIndex: mainIndex)]
    }

    func toggle() { isActive ? stop() : startPreferred() }

    func startPreferred() {
        if let screen = preferredScreen() { start(on: screen) }
    }

    func start(screenID: CGDirectDisplayID) {
        if let screen = NSScreen.screens.first(where: { $0.displayID == screenID }) {
            start(on: screen)
        }
    }

    func start(on screen: NSScreen) {
        let isExternal = screen != NSScreen.main
        let hosting = NSHostingController(rootView: OutputView(live: live))

        let win = window ?? makeWindow(external: isExternal, screen: screen)
        win.contentViewController = hosting
        win.isOpaque = true
        win.backgroundColor = .black

        if isExternal {
            win.styleMask = .borderless
            win.level = .floating
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            win.isMovable = false
            win.setFrame(screen.frame, display: true)
        } else {
            win.title = "Audience Output (Preview)"
            win.center()
        }

        win.makeKeyAndOrderFront(nil)
        window = win
        isActive = true
        activeScreenID = screen.displayID
    }

    func stop() {
        window?.orderOut(nil)
        window = nil
        isActive = false
        activeScreenID = nil
    }

    private func makeWindow(external: Bool, screen: NSScreen) -> NSWindow {
        if external {
            return NSWindow(contentRect: screen.frame, styleMask: .borderless,
                            backing: .buffered, defer: false)
        }
        return NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
                        styleMask: [.titled, .closable, .resizable],
                        backing: .buffered, defer: false)
    }

    @objc private func screensChanged() {
        refreshScreens()
        guard isActive, let id = activeScreenID else { return }

        if let screen = NSScreen.screens.first(where: { $0.displayID == id }) {
            if screen != NSScreen.main { window?.setFrame(screen.frame, display: true) }
        } else if let fallback = preferredScreen() {
            start(on: fallback)   // active display vanished — move to a remaining one
        } else {
            stop()
        }
    }
}
