//
//  main.swift
//  PlasmaDemo
//
//  App entry point: window + MTKView, or a headless --selftest that just
//  verifies the Metal pipeline and scrolltext texture can be built.
//

import AppKit
import MetalKit

// MARK: - Headless self-test (no window)

if CommandLine.arguments.contains("--selftest") {
    guard let device = MTLCreateSystemDefaultDevice() else {
        fputs("selftest FAILED: no Metal device available\n", stderr)
        exit(1)
    }
    do {
        let renderer = try Renderer(device: device, pixelFormat: .bgra8Unorm)
        print("selftest OK — pipeline built, scrolltext texture "
              + "\(renderer.textTexture.width)x\(renderer.textTexture.height), "
              + "C64 scrolltext texture "
              + "\(renderer.textTexture2.width)x\(renderer.textTexture2.height)")
        exit(0)
    } catch {
        fputs("selftest FAILED: \(error)\n", stderr)
        exit(1)
    }
}

// MARK: - Demo view (Esc to quit)

final class DemoView: MTKView {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            NSApp.terminate(nil)
        } else if event.keyCode == 49 { // Space — fade to the next part
            (delegate as? Renderer)?.advanceScene()
        } else {
            super.keyDown(with: event)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - App setup

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.regular)

let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(NSMenuItem(title: "Quit PlasmaDemo",
                           action: #selector(NSApplication.terminate(_:)),
                           keyEquivalent: "q"))
appMenuItem.submenu = appMenu
app.mainMenu = mainMenu

guard let device = MTLCreateSystemDefaultDevice() else {
    fputs("error: no Metal device available\n", stderr)
    exit(1)
}

let frame = NSRect(x: 0, y: 0, width: 960, height: 600)
let window = NSWindow(contentRect: frame,
                      styleMask: [.titled, .closable, .miniaturizable, .resizable],
                      backing: .buffered,
                      defer: false)
window.title = "Plasma + Bouncing Scroller — Swift & Metal"

let view = DemoView(frame: frame, device: device)
view.colorPixelFormat = .bgra8Unorm
view.preferredFramesPerSecond = 60

let renderer: Renderer
do {
    renderer = try Renderer(device: device, pixelFormat: view.colorPixelFormat)
} catch {
    fputs("error: failed to set up renderer: \(error)\n", stderr)
    exit(1)
}
view.delegate = renderer

window.contentView = view
window.center()
window.makeKeyAndOrderFront(nil)
window.makeFirstResponder(view)

app.activate(ignoringOtherApps: true)
app.run()
