import AppKit
import ApplicationServices
import CoreImage
import Darwin
import Foundation

private let port: UInt16 = 8765
private let targetBundleID = "com.jo32.yingxia.mac"
private let keyCodes = [
    "up": 126, "down": 125, "left": 123, "right": 124,
    "select": 36, "back": 53, "play": 49, "fullscreen": 3, "mute": 46,
]

private struct CommandResult {
    let status: Int32
    let output: String
    let error: String
}

private func run(_ executable: URL, _ arguments: [String]) -> CommandResult {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    do { try process.run() }
    catch { return CommandResult(status: 1, output: "", error: error.localizedDescription) }
    if finished.wait(timeout: .now() + 12) == .timedOut {
        process.terminate()
        return CommandResult(status: 1, output: "", error: "操作超时")
    }
    return CommandResult(
        status: process.terminationStatus,
        output: String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
        error: String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    )
}

private func wifiAddress() -> String? {
    for name in ["en0", "en1"] {
        let result = run(URL(fileURLWithPath: "/usr/sbin/ipconfig"), ["getifaddr", name])
        if result.status == 0 && !result.output.isEmpty { return result.output }
    }
    return nil
}

private func actionableError(_ message: String) -> String {
    if message.contains("无法读取映匣窗口") {
        return "请在系统设置 → 隐私与安全性 → 辅助功能中允许映匣遥控器，然后重新打开应用"
    }
    return message
}

private struct Response {
    let status: Int
    let body: Data
    let contentType: String

    init(_ status: Int, _ message: String) {
        self.status = status
        body = Data(message.utf8)
        contentType = "text/plain; charset=utf-8"
    }

    init(_ status: Int, data: Data, contentType: String) {
        self.status = status
        body = data
        self.contentType = contentType
    }

    var encoded: Data {
        let reason = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found",
                      409: "Conflict", 413: "Payload Too Large", 415: "Unsupported Media Type", 500: "Internal Server Error"][status] ?? "Error"
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(header.utf8) + body
    }
}

private final class RemoteServer {
    let address: String
    private let resources: URL
    private let helper: URL
    private let page: Data
    private var socketFD: Int32 = -1
    private var highlight: Process?
    private var highlightInput: FileHandle?
    private let commandQueue = DispatchQueue(label: "YingxiaRemote.commands")
    private var selection: (Double, Double)?
    private var menuOpen = false
    var onFailure: ((String) -> Void)?

    init(address: String) throws {
        self.address = address
        resources = Bundle.main.resourceURL!
        helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ax_remote")
        page = try Data(contentsOf: resources.appendingPathComponent("index.html"))
    }

    func start() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw NSError(domain: "YingxiaRemote", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法创建网络服务"]) }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
        var socketAddress = sockaddr_in()
        socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socketAddress.sin_family = sa_family_t(AF_INET)
        socketAddress.sin_port = port.bigEndian
        guard address.withCString({ inet_pton(AF_INET, $0, &socketAddress.sin_addr) }) == 1 else {
            close(fd)
            throw NSError(domain: "YingxiaRemote", code: 2, userInfo: [NSLocalizedDescriptionKey: "Wi-Fi 地址无效"])
        }
        let bound = withUnsafePointer(to: &socketAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 && listen(fd, 16) == 0 else {
            close(fd)
            throw NSError(domain: "YingxiaRemote", code: 3, userInfo: [NSLocalizedDescriptionKey: "端口 8765 已被占用；请先停止旧版服务"])
        }
        socketFD = fd
        startHighlight()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.acceptConnections() }
    }

    func stop() {
        if socketFD >= 0 { close(socketFD); socketFD = -1 }
        highlightInput?.closeFile()
        if highlight?.isRunning == true { highlight?.terminate() }
    }

    private func startHighlight() {
        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/highlight")
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        highlight = process
        highlightInput = input.fileHandleForWriting
    }

    private func acceptConnections() {
        while socketFD >= 0 {
            let client = accept(socketFD, nil, nil)
            if client < 0 { break }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.handle(client) }
        }
    }

    private func handle(_ client: Int32) {
        defer { close(client) }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        var noPipe: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noPipe, socklen_t(MemoryLayout.size(ofValue: noPipe)))
        var bytes = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while bytes.count < 16384 {
            let count = Darwin.read(client, &chunk, chunk.count)
            if count <= 0 { return }
            bytes.append(contentsOf: chunk.prefix(count))
            guard let separator = bytes.range(of: Data("\r\n\r\n".utf8)) else { continue }
            guard let header = String(data: bytes[..<separator.lowerBound], encoding: .utf8) else { send(client, Response(400, "请求格式错误")); return }
            let lines = header.components(separatedBy: "\r\n")
            let request = lines[0].split(separator: " ")
            guard request.count >= 2 else { send(client, Response(400, "请求格式错误")); return }
            var fields: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                fields[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
            let length = Int(fields["content-length"] ?? "0") ?? -1
            if length < 0 { send(client, Response(400, "请求格式错误")); return }
            if length > 100 { send(client, Response(413, "指令过长")); return }
            let body = bytes[separator.upperBound...]
            if body.count < length { continue }
            let response = commandQueue.sync {
                route(method: String(request[0]), path: String(request[1]), fields: fields, body: Data(body.prefix(length)))
            }
            send(client, response)
            return
        }
        send(client, Response(413, "请求过长"))
    }

    private func send(_ client: Int32, _ response: Response) {
        let data = response.encoded
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < raw.count {
                let count = Darwin.write(client, base.advanced(by: sent), raw.count - sent)
                if count <= 0 { return }
                sent += count
            }
        }
    }

    private func route(method: String, path: String, fields: [String: String], body: Data) -> Response {
        let pathname = String(path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        if method == "GET" && pathname == "/" { return Response(200, data: page, contentType: "text/html; charset=utf-8") }
        if method == "GET" && pathname == "/status" { return Response(200, "已连接") }
        if method == "GET" && pathname.hasPrefix("/icons/") {
            let name = String(pathname.dropFirst("/icons/".count))
            guard name.hasSuffix(".svg"), !name.contains("/"), !name.contains(".."),
                  let data = try? Data(contentsOf: resources.appendingPathComponent("icons").appendingPathComponent(name)) else { return Response(404, "图标不存在") }
            return Response(200, data: data, contentType: "image/svg+xml")
        }
        guard method == "POST" && pathname == "/command" else { return Response(404, "页面不存在") }
        let expectedHost = "\(address):\(port)"
        guard fields["host"] == expectedHost else { return Response(403, "请通过菜单栏显示的地址访问遥控器") }
        if let origin = fields["origin"], origin != "http://\(expectedHost)" { return Response(403, "仅允许从遥控器页面操作") }
        guard fields["content-type"]?.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) == "application/json" else { return Response(415, "仅接受 JSON 指令") }
        guard let request = (try? JSONSerialization.jsonObject(with: body)) as? [String: String],
              let mode = request["mode"], ["browse", "player"].contains(mode),
              let command = request["command"] else { return Response(400, "指令格式错误") }
        if command == "volume_up" || command == "volume_down" { return volume(command == "volume_up" ? 5 : -5) }
        if command == "activate" { return activate(mode) }
        if mode == "browse" {
            guard ["up", "down", "left", "right", "select", "back", "context"].contains(command) else { return Response(400, "未知按键") }
            return browse(command)
        }
        guard let key = keyCodes[command] else { return Response(400, "未知按键") }
        let player = run(helper, ["activate", "player"])
        if player.status != 0 { return Response(409, actionableError(player.error.isEmpty ? "没有正在播放的窗口" : player.error)) }
        updateHighlight(nil)
        let result = keyPress(command == "select" ? keyCodes["play"]! : key)
        return result.status == 0 ? Response(200, "ok") : Response(409, result.error)
    }

    private func activate(_ mode: String) -> Response {
        var result = run(helper, ["activate", mode])
        var leftFullScreen = false
        if mode == "browse" && result.error.contains("全屏播放器正在遮挡主窗口") {
            let player = run(helper, ["activate", "player"])
            if player.status == 0 && keyPress(keyCodes["back"]!).status == 0 {
                Thread.sleep(forTimeInterval: 0.45)
                result = run(helper, ["activate", "browse"])
                leftFullScreen = result.status == 0
            }
        }
        if result.status != 0 { return Response(409, actionableError(result.error.isEmpty ? "无法切换映匣窗口" : result.error)) }
        selection = nil
        menuOpen = false
        updateHighlight(nil)
        return Response(200, result.output + (leftFullScreen ? "（已退出播放全屏）" : ""))
    }

    private func browse(_ command: String) -> Response {
        if menuOpen && command != "context" {
            let result = keyPress(keyCodes[command]!)
            if result.status != 0 { return Response(409, result.error) }
            if command == "select" || command == "back" { menuOpen = false }
            return Response(200, "菜单操作：\(command)")
        }
        let arguments: [String]
        if command == "back" { arguments = ["back"] }
        else {
            let action = command == "select" ? "press" : (command == "context" ? "context" : "move")
            arguments = [action, command, selection.map { String($0.0) } ?? "none", selection.map { String($0.1) } ?? "none"]
        }
        let result = run(helper, arguments)
        if result.status != 0 { return Response(409, actionableError(result.error.isEmpty ? "无法操作映匣主窗口" : result.error)) }
        guard let data = result.output.data(using: .utf8),
              let target = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let x = target["x"] as? Double, let y = target["y"] as? Double,
              let label = target["label"] as? String else { return Response(500, "无法读取选中项") }
        selection = ["up", "down", "left", "right"].contains(command) ? (x, y) : nil
        if command == "context" { menuOpen = true }
        updateHighlight(selection == nil ? nil : data)
        let verb = selection != nil ? "已选中" : (command == "context" ? "已发送右键" : "已操作")
        let shortLabel = label.count > 24 ? String(label.prefix(24)) + "…" : label
        return Response(200, "\(verb)：\(shortLabel)")
    }

    private func keyPress(_ code: Int) -> CommandResult {
        let script = """
        tell application "System Events"
        set frontApp to first application process whose frontmost is true
        if bundle identifier of frontApp is not "\(targetBundleID)" then error "请先将映匣窗口切到 Mac 前台" number 9001
        key code \(code)
        end tell
        """
        return run(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", script])
    }

    private func volume(_ change: Int) -> Response {
        let script = """
        set currentVolume to output volume of (get volume settings)
        set nextVolume to currentVolume + (\(change))
        if nextVolume < 0 then set nextVolume to 0
        if nextVolume > 100 then set nextVolume to 100
        set volume output volume nextVolume
        return output volume of (get volume settings)
        """
        let result = run(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", script])
        return result.status == 0 ? Response(200, "Mac 音量：\(result.output)%") : Response(409, result.error)
    }

    private func updateHighlight(_ target: Data?) {
        guard highlight?.isRunning == true, let input = highlightInput else { return }
        input.write((target ?? Data("{}".utf8)) + Data("\n".utf8))
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var server: RemoteServer?
    private var statusItem: NSStatusItem?
    private var addressItem: NSMenuItem?
    private var address: String?
    private var connectionWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "tv", accessibilityDescription: "映匣遥控器")
        if item.button?.image == nil { item.button?.title = "遥控" }
        let menu = NSMenu()
        let title = NSMenuItem(title: "映匣遥控器", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        let addressItem = NSMenuItem(title: "正在启动…", action: nil, keyEquivalent: "")
        addressItem.isEnabled = false
        menu.addItem(addressItem)
        menu.addItem(NSMenuItem(title: "显示连接窗口", action: #selector(showConnectionWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "复制手机地址", action: #selector(copyAddress), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "在浏览器中打开", action: #selector(openAddress), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "打开辅助功能设置", action: #selector(openAccessibilitySettings), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        for menuItem in menu.items { menuItem.target = self }
        item.menu = menu
        statusItem = item
        self.addressItem = addressItem
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(prompt)
        guard let ip = wifiAddress() else {
            addressItem.title = "未找到 Wi-Fi 地址"
            showConnectionWindow()
            return
        }
        do {
            let server = try RemoteServer(address: ip)
            try server.start()
            self.server = server
            address = "http://\(ip):\(port)/"
            addressItem.title = address!
        } catch { addressItem.title = error.localizedDescription }
        showConnectionWindow()
    }

    func applicationWillTerminate(_ notification: Notification) { server?.stop() }

    @objc private func copyAddress() {
        guard let address else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
    }

    @objc private func openAddress() {
        guard let address, let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func showConnectionWindow() {
        if let connectionWindow {
            connectionWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: address == nil ? 230 : 470),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "映匣遥控器"
        window.isReleasedWhenClosed = false
        let content = NSView()
        window.contentView = content

        let title = NSTextField(labelWithString: "用手机控制 Mac 上的映匣")
        title.font = .boldSystemFont(ofSize: 18)
        let instruction = NSTextField(wrappingLabelWithString: "手机与 Mac 连接同一 Wi-Fi，扫码或打开下面的地址。关闭窗口后，遥控器仍在菜单栏运行。")
        instruction.textColor = .secondaryLabelColor
        instruction.alignment = .center
        let addressLabel = NSTextField(labelWithString: address ?? addressItem?.title ?? "正在启动…")
        addressLabel.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        addressLabel.isSelectable = true
        let permission = NSTextField(wrappingLabelWithString: AXIsProcessTrusted()
            ? "辅助功能已允许"
            : "首次使用请在系统设置中允许“映匣遥控器”访问辅助功能，然后重新打开应用。")
        permission.textColor = .secondaryLabelColor
        permission.alignment = .center

        let copyButton = NSButton(title: "复制手机地址", target: self, action: #selector(copyAddress))
        let settingsButton = NSButton(title: "打开辅助功能设置", target: self, action: #selector(openAccessibilitySettings))
        let buttons = NSStackView(views: [copyButton, settingsButton])
        buttons.spacing = 12
        var views: [NSView] = [title, instruction]
        if let address, let qrImage = qrCode(for: address) {
            let card = NSView()
            card.wantsLayer = true
            card.layer?.backgroundColor = NSColor.white.cgColor
            card.layer?.cornerRadius = 14
            let code = NSImageView(image: qrImage)
            code.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(code)
            NSLayoutConstraint.activate([
                card.widthAnchor.constraint(equalToConstant: 196),
                card.heightAnchor.constraint(equalToConstant: 196),
                code.widthAnchor.constraint(equalToConstant: 180),
                code.heightAnchor.constraint(equalToConstant: 180),
                code.centerXAnchor.constraint(equalTo: card.centerXAnchor),
                code.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            ])
            views.append(card)
        }
        views.append(contentsOf: [addressLabel, permission, buttons])
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            instruction.widthAnchor.constraint(lessThanOrEqualToConstant: 392),
            permission.widthAnchor.constraint(lessThanOrEqualToConstant: 392),
        ])
        window.center()
        connectionWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func qrCode(for address: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(address.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 180, height: 180))
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
