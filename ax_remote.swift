import AppKit
import ApplicationServices

let bundleID = "com.jo32.yingxia.mac"

struct Target {
    let element: AXUIElement
    let frame: CGRect
    let label: String
    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
}

func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
    return value
}

func stringAttribute(_ element: AXUIElement, _ key: String) -> String {
    attribute(element, key) as? String ?? ""
}

func axValue(_ element: AXUIElement, _ key: String, type: AXValueType) -> AXValue? {
    guard let raw = attribute(element, key), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
    let value = raw as! AXValue
    return AXValueGetType(value) == type ? value : nil
}

func frame(_ element: AXUIElement) -> CGRect? {
    guard let positionValue = axValue(element, kAXPositionAttribute, type: .cgPoint),
          let sizeValue = axValue(element, kAXSizeAttribute, type: .cgSize) else { return nil }
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue, .cgPoint, &position),
          AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
    return CGRect(origin: position, size: size)
}

func canPress(_ element: AXUIElement) -> Bool {
    var actions: CFArray?
    guard AXUIElementCopyActionNames(element, &actions) == .success else { return false }
    return (actions as? [String])?.contains(kAXPressAction as String) == true
}

func collect(_ element: AXUIElement, inside window: CGRect, depth: Int = 0) -> [Target] {
    guard depth < 25 else { return [] }
    var targets: [Target] = []
    let role = stringAttribute(element, kAXRoleAttribute)
    if role == kAXButtonRole as String || role == "AXLink" {
        let description = stringAttribute(element, kAXDescriptionAttribute)
        let label = description.isEmpty ? stringAttribute(element, kAXTitleAttribute) : description
        if let bounds = frame(element), bounds.width >= 12, bounds.height >= 12,
           !(bounds.width > 500 && bounds.height < 80), canPress(element),
           window.contains(CGPoint(x: bounds.midX, y: bounds.midY)),
           bounds.midY < window.maxY - 44, !label.isEmpty {
            targets.append(Target(element: element, frame: bounds, label: label))
        }
    }
    if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
        for child in children { targets += collect(child, inside: window, depth: depth + 1) }
    }
    return targets
}

func choose(_ targets: [Target], direction: String, from origin: CGPoint?) -> Target? {
    guard !targets.isEmpty else { return nil }
    guard let origin else {
        let leftEdge = targets.map(\.frame.minX).min()!
        let content = targets.filter { $0.center.x > leftEdge + 250 }
        let cards = content.filter { $0.frame.width >= 80 && $0.frame.height >= 80 }
        return (cards.isEmpty ? (content.isEmpty ? targets : content) : cards).min {
            ($0.center.y, $0.center.x) < ($1.center.y, $1.center.x)
        }
    }
    let candidates = targets.compactMap { target -> (Target, CGFloat)? in
        let dx = target.center.x - origin.x
        let dy = target.center.y - origin.y
        let forward: CGFloat
        let sideways: CGFloat
        switch direction {
        case "up": forward = -dy; sideways = abs(dx)
        case "down": forward = dy; sideways = abs(dx)
        case "left": forward = -dx; sideways = abs(dy)
        case "right": forward = dx; sideways = abs(dy)
        default: return nil
        }
        guard forward > 8 else { return nil }
        if (direction == "up" || direction == "down") && sideways > 220 { return nil }
        return (target, forward + sideways * 2)
    }
    return candidates.min { $0.1 < $1.1 }?.0
}

func nextAfterScroll(_ targets: [Target], window: AXUIElement, direction: String, origin: CGPoint) -> Target? {
    guard direction == "up" || direction == "down", let bounds = frame(window),
          var current = targets.min(by: {
              hypot($0.center.x - origin.x, $0.center.y - origin.y) <
              hypot($1.center.x - origin.x, $1.center.y - origin.y)
          }) else { return nil }
    let natural = UserDefaults.standard.bool(forKey: "com.apple.swipescrolldirection")
    let amount: Int32 = (direction == "down") == natural ? 2 : -2
    for _ in 0..<25 {
        let anchor = CGPoint(x: current.center.x,
                             y: min(max(current.center.y, bounds.minY + 80), bounds.maxY - 80))
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: anchor, mouseButton: .left)?.post(tap: .cghidEventTap)
        if let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                               wheel1: amount, wheel2: 0, wheel3: 0) {
            wheel.location = anchor
            wheel.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.025)
        let refreshed = collect(window, inside: bounds)
        guard let moved = refreshed.filter({ $0.label == current.label }).min(by: {
            abs($0.center.x - current.center.x) < abs($1.center.x - current.center.x)
        }) else { return nil }
        if abs(moved.center.y - current.center.y) < 2 { continue }
        let content = refreshed.filter {
            $0.center.x > bounds.minX + 260 && $0.center.y > bounds.minY + 80
        }
        if let next = choose(content, direction: direction, from: moved.center),
           next.frame.minY > bounds.minY + 30,
           next.frame.maxY < bounds.maxY - 30 { return next }
        current = moved
    }
    return current
}

func output(_ target: Target) {
    let data: [String: Any] = ["x": target.center.x, "y": target.center.y,
                               "width": target.frame.width, "height": target.frame.height,
                               "label": target.label]
    let json = try! JSONSerialization.data(withJSONObject: data)
    print(String(decoding: json, as: UTF8.self))
}

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    fputs("映匣未运行\n", stderr)
    exit(1)
}
let application = AXUIElementCreateApplication(app.processIdentifier)
guard let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement] else {
    fputs("无法读取映匣窗口，请检查辅助功能权限\n", stderr)
    exit(1)
}
let candidates = windows.compactMap { window -> (AXUIElement, [Target])? in
    guard let bounds = frame(window) else { return nil }
    return (window, collect(window, inside: bounds))
}
func isBrowseWindow(_ candidate: (AXUIElement, [Target])) -> Bool {
    if candidate.1.contains(where: { $0.label == "现在观看" || $0.label == "Watch Now" }) { return true }
    guard let bounds = frame(candidate.0) else { return false }
    return stringAttribute(candidate.0, kAXTitleAttribute).isEmpty &&
           bounds.width > 800 && bounds.height > 600 && candidate.1.count >= 3
}
let main = candidates.first(where: isBrowseWindow)
let args = Array(CommandLine.arguments.dropFirst())
guard let action = args.first else { exit(2) }
if action == "activate" {
    guard args.count == 2 else { exit(2) }
    let targetWindow: AXUIElement?
    if args[1] == "browse" { targetWindow = main?.0 }
    else if args[1] == "player" {
        let players = candidates.filter { candidate in
            guard let bounds = frame(candidate.0) else { return false }
            return bounds.width > 400 && bounds.height > 300 &&
                   !isBrowseWindow(candidate) && !stringAttribute(candidate.0, kAXTitleAttribute).isEmpty
        }
        targetWindow = (players.first { attribute($0.0, "AXFullScreen") as? Bool == true }
                     ?? players.first { attribute($0.0, kAXMainAttribute) as? Bool == true }
                     ?? players.first)?.0
    } else { exit(2) }
    guard let targetWindow else {
        if args[1] == "browse" && candidates.contains(where: {
            !stringAttribute($0.0, kAXTitleAttribute).isEmpty &&
            attribute($0.0, "AXFullScreen") as? Bool == true
        }) {
            fputs("全屏播放器正在遮挡主窗口\n", stderr)
        } else {
            fputs(args[1] == "browse" ? "映匣主窗口未打开；请在 Mac 上通过「文件 > 新建窗口」打开一次\n" : "没有正在播放的窗口\n", stderr)
        }
        exit(1)
    }
    _ = app.activate()
    let raised = AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
    let madeMain = AXUIElementSetAttributeValue(targetWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
    guard raised == .success || madeMain == .success else {
        fputs("无法切换映匣窗口（\(raised.rawValue), \(madeMain.rawValue)）\n", stderr)
        exit(1)
    }
    print(args[1] == "browse" ? "主界面已前置" : "播放窗口已前置")
    exit(0)
}
guard let (window, targets) = main else {
    fputs("未找到映匣主窗口；请先打开主窗口\n", stderr)
    exit(1)
}

if action == "list" {
    for target in targets { print("\(Int(target.center.x)),\(Int(target.center.y))\t\(target.label)") }
    exit(0)
}
_ = app.activate()
_ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
_ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
if action == "back" {
    guard let target = targets.first(where: { $0.label == "返回" || $0.label == "Back" }),
          AXUIElementPerformAction(target.element, kAXPressAction as CFString) == .success else {
        fputs("当前页面没有可用的返回按钮\n", stderr)
        exit(1)
    }
    output(target)
    exit(0)
}
guard args.count == 4 else { exit(2) }
let point: CGPoint? = args[2] == "none" ? nil : {
    guard let x = Double(args[2]), let y = Double(args[3]) else { return nil }
    let point = CGPoint(x: x, y: y)
    return frame(window)?.contains(point) == true ? point : nil
}()
if action == "press" || action == "context" {
    guard let point, let target = targets.min(by: {
        hypot($0.center.x - point.x, $0.center.y - point.y) < hypot($1.center.x - point.x, $1.center.y - point.y)
    }) else {
        fputs("当前控件无法点击\n", stderr)
        exit(1)
    }
    if action == "context" {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: target.center, mouseButton: .right)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown,
                mouseCursorPosition: target.center, mouseButton: .right)?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.08)
        CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp,
                mouseCursorPosition: target.center, mouseButton: .right)?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.08)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let menuIsVisible = windows.contains { window in
            let owner = window[kCGWindowOwnerPID as String] as? Int
            let layer = window[kCGWindowLayer as String] as? Int
            return owner == Int(app.processIdentifier) && layer == 101
        }
        guard menuIsVisible else {
            fputs("此项没有更多操作\n", stderr)
            exit(1)
        }
    } else if AXUIElementPerformAction(target.element, kAXPressAction as CFString) != .success {
        fputs("当前控件无法点击\n", stderr)
        exit(1)
    }
    output(target)
    exit(0)
}
guard action == "move" else { exit(2) }
let shouldScroll = point.map { origin in
    guard let bounds = frame(window) else { return false }
    guard origin.x > bounds.minX + 260 else { return false }
    if args[1] == "down" { return origin.y > bounds.minY + bounds.height * 0.64 }
    if args[1] == "up" { return origin.y < bounds.minY + bounds.height * 0.45 }
    return false
} ?? false
let scrolledTarget = shouldScroll ? point.flatMap {
    nextAfterScroll(targets, window: window, direction: args[1], origin: $0)
} : nil
let target = scrolledTarget ?? choose(targets, direction: args[1], from: point)
    ?? point.flatMap { nextAfterScroll(targets, window: window, direction: args[1], origin: $0) }
guard let target else {
    fputs("这个方向没有可选控件\n", stderr)
    exit(1)
}
if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: target.center, mouseButton: .left) {
    event.post(tap: .cghidEventTap)
}
output(target)
