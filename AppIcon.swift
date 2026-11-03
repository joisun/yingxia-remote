import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 216, yRadius: 216)
let backgroundShadow = NSShadow()
backgroundShadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
backgroundShadow.shadowBlurRadius = 44
backgroundShadow.shadowOffset = NSSize(width: 0, height: -22)
backgroundShadow.set()
NSGradient(starting: NSColor(calibratedRed: 0.18, green: 0.24, blue: 0.30, alpha: 1),
           ending: NSColor(calibratedRed: 0.055, green: 0.08, blue: 0.12, alpha: 1))!.draw(in: background, angle: -55)
NSShadow().set()
background.lineWidth = 3
NSColor(calibratedWhite: 0.54, alpha: 0.35).setStroke()
background.stroke()

let glow = NSBezierPath(ovalIn: NSRect(x: 238, y: 146, width: 548, height: 748))
let glowShadow = NSShadow()
glowShadow.shadowColor = NSColor(calibratedRed: 0.35, green: 0.83, blue: 0.84, alpha: 0.21)
glowShadow.shadowBlurRadius = 100
glowShadow.set()
NSColor(calibratedWhite: 1, alpha: 0.015).setFill()
glow.fill()
NSShadow().set()

NSGraphicsContext.current?.saveGraphicsState()
let rotation = NSAffineTransform()
rotation.translateX(by: 512, yBy: 512)
rotation.rotate(byDegrees: -14)
rotation.translateX(by: -512, yBy: -512)
rotation.concat()

let remote = NSBezierPath(roundedRect: NSRect(x: 328, y: 134, width: 368, height: 756), xRadius: 116, yRadius: 116)
let remoteShadow = NSShadow()
remoteShadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
remoteShadow.shadowBlurRadius = 42
remoteShadow.shadowOffset = NSSize(width: 20, height: -24)
remoteShadow.set()
NSGradient(starting: NSColor(calibratedWhite: 0.96, alpha: 1),
           ending: NSColor(calibratedWhite: 0.57, alpha: 1))!.draw(in: remote, angle: -20)
NSShadow().set()
remote.lineWidth = 5
NSColor(calibratedWhite: 1, alpha: 0.78).setStroke()
remote.stroke()

let touchpad = NSBezierPath(ovalIn: NSRect(x: 364, y: 498, width: 296, height: 296))
NSGradient(starting: NSColor(calibratedWhite: 0.20, alpha: 1),
           ending: NSColor(calibratedWhite: 0.055, alpha: 1))!.draw(in: touchpad, angle: 120)
touchpad.lineWidth = 9
NSColor(calibratedWhite: 0.47, alpha: 1).setStroke()
touchpad.stroke()

let select = NSBezierPath(ovalIn: NSRect(x: 458, y: 592, width: 108, height: 108))
NSColor(calibratedWhite: 0.24, alpha: 1).setFill()
select.fill()
select.lineWidth = 5
NSColor(calibratedWhite: 0.56, alpha: 1).setStroke()
select.stroke()

let play = NSBezierPath()
play.move(to: NSPoint(x: 502, y: 616))
play.line(to: NSPoint(x: 502, y: 676))
play.line(to: NSPoint(x: 550, y: 646))
play.close()
NSColor(calibratedRed: 0.46, green: 0.94, blue: 0.85, alpha: 1).setFill()
play.fill()

let back = NSBezierPath(roundedRect: NSRect(x: 376, y: 326, width: 118, height: 92), xRadius: 46, yRadius: 46)
NSColor(calibratedWhite: 0.17, alpha: 1).setFill()
back.fill()
let pause = NSBezierPath(roundedRect: NSRect(x: 530, y: 326, width: 118, height: 92), xRadius: 46, yRadius: 46)
NSColor(calibratedWhite: 0.17, alpha: 1).setFill()
pause.fill()

let backArrow = NSBezierPath()
backArrow.move(to: NSPoint(x: 462, y: 372))
backArrow.line(to: NSPoint(x: 412, y: 372))
backArrow.line(to: NSPoint(x: 432, y: 392))
backArrow.move(to: NSPoint(x: 412, y: 372))
backArrow.line(to: NSPoint(x: 432, y: 352))
backArrow.lineWidth = 8
backArrow.lineCapStyle = .round
backArrow.lineJoinStyle = .round
NSColor(calibratedWhite: 0.89, alpha: 1).setStroke()
backArrow.stroke()

let pauseMark = NSBezierPath(roundedRect: NSRect(x: 568, y: 348, width: 9, height: 46), xRadius: 4, yRadius: 4)
pauseMark.appendRoundedRect(NSRect(x: 596, y: 348, width: 9, height: 46), xRadius: 4, yRadius: 4)
NSColor(calibratedWhite: 0.89, alpha: 1).setFill()
pauseMark.fill()

NSGraphicsContext.current?.restoreGraphicsState()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
