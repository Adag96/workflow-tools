// gamify_scroll — horizontal swipe/scroll → spins the Gamify length carousel.
//
// sketchybar's mouse.scrolled only reports the vertical delta (a sideways swipe arrives
// with SCROLL_DELTA=0), so while the start menu is open, gamify_menu.sh runs this helper.
// It watches scroll events globally (no permission needed for mouse events), and when the
// cursor is over the pill turns horizontal travel into carousel steps:
//   gamify_menu.sh spin <±n>        (one notch per STEP points; trackpad momentum included,
//                                    so a flick keeps it turning like a dial)
// Content moving left (fingers swiping left with natural scrolling) brings the right-hand
// neighbour to the centre, i.e. a longer session.
// It exits when the menu closes (checked every second) — gamify_menu.sh also kills it.
//
// Build: swiftc -O gamify_scroll.swift -o <bin>   (items/gamify.sh does this on load)
// Usage: gamify_scroll <menu script> <pill x0> <pill x1> <bar height>

import AppKit

let args = CommandLine.arguments
guard args.count == 5, let x0 = Double(args[2]), let x1 = Double(args[3]),
      let barH = Double(args[4]) else {
    FileHandle.standardError.write("usage: gamify_scroll <menu script> <x0> <x1> <bar height>\n".data(using: .utf8)!)
    exit(2)
}
let script = args[1]
let STEP = 28.0           // points of horizontal travel per notch (trackpad)
let LINE = 10.0           // a non-precise wheel "line" counts as this many points

var travel = 0.0          // accumulated, not yet turned into notches
var pending = 0           // notches waiting for the menu script
var busy = false

func runMenu(_ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: script)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
}

// One spin call at a time; notches that arrive meanwhile are summed into the next call
func drain() {
    guard !busy, pending != 0 else { return }
    let n = pending
    pending = 0
    busy = true
    DispatchQueue.global().async {
        _ = runMenu(["spin", String(n)])
        DispatchQueue.main.async { busy = false; drain() }
    }
}

func overPill() -> Bool {
    let p = NSEvent.mouseLocation                         // bottom-left origin
    let y = NSScreen.screens[0].frame.height - p.y        // → bar coordinates
    return p.x >= x0 && p.x <= x1 && y >= 0 && y <= barH
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)                      // no Dock icon, never focused

NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { e in
    if e.phase == .began { travel = 0 }
    var dx = Double(e.scrollingDeltaX), dy = Double(e.scrollingDeltaY)
    if !e.hasPreciseScrollingDeltas { dx *= LINE; dy *= LINE }
    guard abs(dx) > abs(dy), overPill() else { return }
    travel -= dx                                          // content left → forward
    let notches = Int(travel / STEP)                      // truncates toward zero
    if notches != 0 {
        travel -= Double(notches) * STEP
        pending += notches
        drain()
    }
}

// Quit once the menu has closed (or sketchybar reloaded under us)
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    DispatchQueue.global().async { if runMenu(["is_open"]) != 0 { exit(0) } }
}

app.run()
