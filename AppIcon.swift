import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let body = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 210, yRadius: 210)
let bodyShadow = NSShadow()
bodyShadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
bodyShadow.shadowBlurRadius = 42
bodyShadow.shadowOffset = NSSize(width: 0, height: -22)
bodyShadow.set()
NSGradient(starting: NSColor(calibratedWhite: 0.95, alpha: 1),
           ending: NSColor(calibratedWhite: 0.61, alpha: 1))!.draw(in: body, angle: -35)
NSShadow().set()

let ring = NSBezierPath(ovalIn: NSRect(x: 200, y: 322, width: 624, height: 624))
NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
ring.fill()
ring.lineWidth = 14
NSColor(calibratedWhite: 0.35, alpha: 1).setStroke()
ring.stroke()

let center = NSBezierPath(ovalIn: NSRect(x: 388, y: 510, width: 248, height: 248))
NSColor(calibratedWhite: 0.23, alpha: 1).setFill()
center.fill()
center.lineWidth = 9
NSColor(calibratedWhite: 0.48, alpha: 1).setStroke()
center.stroke()

func chevron(_ points: [NSPoint]) {
    let path = NSBezierPath()
    path.move(to: points[0])
    path.line(to: points[1])
    path.line(to: points[2])
    path.lineWidth = 16
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    NSColor(calibratedWhite: 0.88, alpha: 1).setStroke()
    path.stroke()
}

chevron([NSPoint(x: 486, y: 844), NSPoint(x: 512, y: 870), NSPoint(x: 538, y: 844)])
chevron([NSPoint(x: 486, y: 424), NSPoint(x: 512, y: 398), NSPoint(x: 538, y: 424)])
chevron([NSPoint(x: 304, y: 658), NSPoint(x: 278, y: 632), NSPoint(x: 304, y: 606)])
chevron([NSPoint(x: 720, y: 658), NSPoint(x: 746, y: 632), NSPoint(x: 720, y: 606)])

let lowerButton = NSBezierPath(roundedRect: NSRect(x: 324, y: 172, width: 376, height: 96), xRadius: 48, yRadius: 48)
NSColor(calibratedWhite: 0.15, alpha: 1).setFill()
lowerButton.fill()

image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
