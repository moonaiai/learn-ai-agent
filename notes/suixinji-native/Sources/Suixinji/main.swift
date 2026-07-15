import AppKit
import Carbon.HIToolbox
import Foundation

// Direct launches (for example from a development terminal) can otherwise
// create a second accessory process. Both processes register Cmd+Enter, so a
// single key press is handled twice and the panel appears unable to close.
// Keep one process per bundle identifier and activate the existing instance.
if let bundleID = Bundle.main.bundleIdentifier {
    let currentPID = ProcessInfo.processInfo.processIdentifier
    if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .first(where: { $0.processIdentifier != currentPID }) {
        existing.activate(options: [.activateIgnoringOtherApps])
        exit(0)
    }
}

// Unbuffered stdout for diagnostic prints.
setbuf(stdout, nil)

// ---- Application bootstrap (mirrors native-probe, which is verified to float
// over fullscreen apps). ----

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon, no Cmd+Tab entry
app.finishLaunching()

let delegate = AppDelegate()
app.delegate = delegate

let panelController = PanelController()
panelController.setup()

// ---- Global hotkey: Cmd+Enter toggles the panel. ----
// Carbon RegisterEventHotKey does NOT require Accessibility permission.
var hotkeyRef: EventHotKeyRef?
var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                              eventKind: UInt32(kEventHotKeyPressed))

let handler: @convention(c) (EventHandlerRef?, EventRef?, UnsafeMutableRawPointer?) -> OSStatus = { _, _, _ in
    DispatchQueue.main.async {
        panelController.toggle()
    }
    return noErr
}

InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventSpec, nil, nil)
let hotkeyId = EventHotKeyID(signature: OSType(0x5358_4A49), id: 1)  // 'SXJI'
RegisterEventHotKey(UInt32(kVK_Return), UInt32(cmdKey), hotkeyId,
                    GetApplicationEventTarget(), 0, &hotkeyRef)

NSLog("[suixinji] launched. Press Cmd+Enter to toggle the panel.")

app.run()
