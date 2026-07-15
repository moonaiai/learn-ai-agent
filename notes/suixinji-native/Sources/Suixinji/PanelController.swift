import AppKit
import CoreGraphics

/// Borderless panels do not become key windows by default. The notes editor
/// needs a real key/main window so NSTextView and toolbar controls receive
/// keyboard and mouse events after the floating panel is shown.
final class InteractivePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The panel itself is intentionally not movable by its entire background:
/// the sidebar contains real drag sources and needs to own those gestures.
/// Only the empty part of the top bar is a window-drag surface.
final class WindowDragView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// Owns the floating NSPanel and the global Cmd+Enter hotkey.
///
/// The panel follows the Space where the global hotkey was pressed and remains
/// eligible to appear above a full-screen application.
final class PanelController: NSObject, NSWindowDelegate {

    private var panel: InteractivePanel!
    private let mainVC = MainViewController()
    private var isPinned = false
    private var resignActiveObserver: NSObjectProtocol?
    private var activeApplicationObserver: NSObjectProtocol?
    private var activeSpaceObserver: NSObjectProtocol?

    func setup() {
        mainVC.delegate = self

        // Borderless and resizable, with no titlebar placeholder. The custom
        // 40px topBar starts at the window's true top edge. This is an
        // interactive panel rather than a nonactivating panel: editing and
        // toolbar controls must receive key/mouse events.
        let panel = InteractivePanel(
            contentRect: NSRect(x: 0, y: 0,
                                width: MainViewController.preferredPanelWidth,
                                height: 520),
            styleMask: [.resizable],
            backing: .buffered,
            defer: false
        )
        // Do not let the window consume mouse drags from note rows. Window
        // dragging is implemented only by WindowDragView in the top bar.
        panel.isMovableByWindowBackground = false
        // Move the panel into the Space active when Cmd+Enter is pressed.
        // `canJoinAllSpaces` makes an accessory panel keep an old Space
        // assignment, which is why it could appear in another window after
        // being hidden and shown again. These two behaviors are mutually
        // exclusive; moveToActiveSpace is the behavior we need here.
        applyCollectionBehavior()
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        // Hide explicitly from didResignActive so pending edits are flushed
        // before the panel disappears. Leaving this AppKit switch off is
        // important for an accessory panel: when it is shown by the global
        // Cmd+Enter hotkey, automatic deactivation handling can restore the
        // panel in the accessory app's previous Space instead of the current
        // window's Space.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = Theme.background
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self

        // Install the main view controller's view DIRECTLY as the content view,
        // mirroring the verified native-probe pattern. We deliberately avoid
        // `panel.contentViewController = mainVC`: assigning a contentViewController
        // whose view has only edge-anchored constraints (no intrinsic width,
        // no intrinsic height on the container/split view) lets AppKit resolve
        // the content size from the view's fittingSize (~0×44), collapsing the
        // 760×520 panel into a one-pixel line. An explicit frame +
        // autoresizingMask keeps the panel at its contentRect size and lets the
        // internal Auto Layout constraints resolve against a real 760×520 canvas.
        let contentView = mainVC.view
        contentView.frame = panel.contentView?.bounds
            ?? NSRect(x: 0, y: 0,
                      width: MainViewController.preferredPanelWidth,
                      height: 520)
        contentView.autoresizingMask = [.width, .height]
        panel.contentView = contentView

        // Use a safe initial frame. Before every actual show, the panel is
        // moved to the screen containing the current frontmost window.
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)
        panel.setFrameOrigin(NSPoint(x: screenFrame.midX - panel.frame.width / 2,
                                     y: screenFrame.midY - panel.frame.height / 2))

        self.panel = panel

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isPinned, self.panel.isVisible else { return }
            self.hide()
        }

        // A pinned panel remains visible while the user changes applications
        // or Spaces. Reposition it to the display containing the newly active
        // window so it follows the current workspace instead of staying on a
        // previous display.
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        activeApplicationObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleFollowActiveWindow()
        }
        activeSpaceObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleFollowActiveWindow()
        }

        // Global key handling within the panel: Esc hides, Cmd+S saves — works
        // regardless of which child control currently has focus.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.panel.isVisible else { return event }
            if event.keyCode == 53 {  // Esc
                // A preview is a separate key window. Esc should close that
                // window first instead of hiding the notes panel underneath it.
                let eventWindow = event.window ?? NSApp.keyWindow
                if let eventWindow, eventWindow !== self.panel {
                    eventWindow.performClose(nil)
                    return nil
                }
                if self.mainVC.editorDidConsumeEscape() {
                    return nil
                }
                self.hide()
                return nil
            }
            if event.modifierFlags.contains(.command),
               let ch = event.charactersIgnoringModifiers, ch.lowercased() == "s" {
                self.mainVC.saveNow()
                return nil
            }
            if event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.shift),
               !event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.control),
               let ch = event.charactersIgnoringModifiers, ch.lowercased() == "n" {
                self.mainVC.createNewNote()
                return nil
            }
            if event.modifierFlags.contains(.command),
               let ch = event.charactersIgnoringModifiers, ch.lowercased() == "v",
               self.mainVC.editorDidConsumePaste() {
                return nil
            }
            return event
        }
    }

    deinit {
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        if let activeApplicationObserver {
            workspaceCenter.removeObserver(activeApplicationObserver)
        }
        if let activeSpaceObserver {
            workspaceCenter.removeObserver(activeSpaceObserver)
        }
    }

    func toggle() {
        if panel.isVisible {
            NSLog("[suixinji] hide (hotkey)")
            hide()
        } else {
            NSLog("[suixinji] show (hotkey)")
            show()
        }
    }

    func show() {
        mainVC.onShow()
        movePanelToFrontmostWindowScreen()
        // Re-apply this before every show. This is important after the panel
        // has been hidden from an external app: AppKit then moves it to the
        // Space currently occupied by that app instead of restoring its old
        // Space assignment.
        applyCollectionBehavior()
        panel.orderFrontRegardless()
        // The app is an accessory app, so explicitly activate it before
        // making the panel key. Without this, the panel can be visible while
        // the previous app remains frontmost and all editor input is lost.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeMain()
        panel.makeKey()
    }

    /// Place the panel on the display that owns the currently frontmost
    /// application window. `NSScreen.main` is the screen with the menu bar,
    /// not necessarily the screen where the user pressed Cmd+Enter; with a
    /// second display that made the panel appear in another window's area.
    private func movePanelToFrontmostWindowScreen() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        var targetScreen: NSScreen?

        if let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]] {
            // CGWindowList returns windows front-to-back. The first normal
            // application window is therefore the one receiving the hotkey.
            for info in windows {
                let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
                guard layer == 0 else { continue }
                let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                guard ownerPID != ownPID else { continue }
                guard let rawBounds = info[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: rawBounds),
                      bounds.width >= 200,
                      bounds.height >= 100 else { continue }

                let centerX = bounds.midX
                targetScreen = NSScreen.screens.first {
                    centerX >= $0.frame.minX && centerX < $0.frame.maxX
                }
                if targetScreen != nil { break }
            }
        }

        if targetScreen == nil {
            let mouse = NSEvent.mouseLocation
            targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
                ?? NSScreen.main
        }
        guard let targetScreen else { return }

        let panelCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let currentScreen = NSScreen.screens.first(where: { $0.frame.contains(panelCenter) })
        guard currentScreen?.frame != targetScreen.frame else { return }

        let visibleFrame = targetScreen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.midY - panel.frame.height / 2
        ))
    }

    private func scheduleFollowActiveWindow() {
        guard isPinned, panel.isVisible else { return }
        // The workspace notification can arrive before the window server has
        // committed the new active window or Space. Defer one run-loop turn so
        // the frontmost-window query sees the new workspace.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPinned, self.panel.isVisible else { return }
            self.movePanelToFrontmostWindowScreen()
        }
    }

    func hide() {
        mainVC.flushBeforeHide()
        panel.orderOut(nil)
    }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        applyCollectionBehavior()
        if pinned, panel.isVisible {
            scheduleFollowActiveWindow()
        }
    }

    private func applyCollectionBehavior() {
        guard panel != nil else { return }
        panel.collectionBehavior = isPinned
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.moveToActiveSpace, .fullScreenAuxiliary]
    }

    // NSWindowDelegate: a programmatic close (e.g. via a menu shortcut) hides
    // the panel instead of closing/terminating. The borderless panel has no
    // close button; primary dismiss paths are Esc + the Cmd+Enter hotkey.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}

extension PanelController: MainViewControllerDelegate {
    func mainDidRequestHide() {
        hide()
    }

    func mainDidTogglePinned(_ pinned: Bool) {
        setPinned(pinned)
    }
}
