import AppKit
import Foundation

final class FocusView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 5), xRadius: 18, yRadius: 18)
        NSColor.white.withAlphaComponent(0.09).setFill()
        outline.fill()

        let shadow = NSShadow()
        shadow.shadowColor = NSColor(red: 0.76, green: 0.86, blue: 1, alpha: 0.75)
        shadow.shadowBlurRadius = 16
        shadow.set()
        outline.lineWidth = 2.5
        NSColor.white.withAlphaComponent(0.92).setStroke()
        outline.stroke()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.ignoresMouseEvents = true
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.hidesOnDeactivate = false
panel.contentView = FocusView(frame: .zero)

DispatchQueue.global(qos: .userInitiated).async {
    while let line = readLine() {
        guard let data = line.data(using: .utf8),
              let command = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
        DispatchQueue.main.async {
            guard let x = command["x"] as? Double, let y = command["y"] as? Double,
                  let width = command["width"] as? Double,
                  let height = command["height"] as? Double else {
                panel.orderOut(nil)
                return
            }
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            let rect = NSRect(x: x - width / 2 - 5, y: top - y - height / 2 - 5,
                              width: width + 10, height: height + 10)
            if panel.isVisible {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().setFrame(rect, display: true)
                }
            } else {
                panel.setFrame(rect, display: true)
            }
            panel.contentView?.needsDisplay = true
            panel.orderFrontRegardless()
        }
    }
    DispatchQueue.main.async { app.terminate(nil) }
}

app.run()
