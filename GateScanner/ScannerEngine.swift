import Foundation
import Network

final class ScannerEngine {
    var onResult: ((ScanResult) -> Void)?
    var onProgress: ((_ scanned: Int, _ total: Int) -> Void)?
    var onStatus: ((String) -> Void)?
    var onComplete: (() -> Void)?

    private var cancelled = false
    let wifiInfo: WiFiInfo

    init() {
        wifiInfo = Self.getWiFiInfo()
    }

    func start() {
        cancelled = false
        let ips = wifiInfo.ipArray()
        guard !ips.isEmpty else {
            onStatus?("未连接 WiFi")
            onComplete?()
            return
        }

        let total = ips.count * Brand.ports.count
        onStatus?("扫描 \(ips.count) 个IP × \(Brand.ports.count) 个端口...")
        onProgress?(0, total)

        Task {
            var scanned = 0
            let sem = AsyncSemaphore(limit: 40)
            var foundResults: [ScanResult] = []

            await withTaskGroup(of: ScanResult?.self) { group in
                for ip in ips {
                    for port in Brand.ports {
                        guard !cancelled else { break }
                        await sem.wait()
                        group.addTask { [weak self] in
                            defer { Task { await sem.signal() } }
                            return await self?.scanOne(ip: ip, port: port)
                        }
                    }
                }

                for await r in group {
                    scanned += 1
                    if let r = r {
                        foundResults.append(r)
                        await MainActor.run { self.onResult?(r) }
                    }
                    await MainActor.run { self.onProgress?(scanned, total) }
                }
            }

            guard !cancelled else {
                await MainActor.run { self.onStatus?("已取消") }
                return
            }

            // Try passwords
            await MainActor.run { self.onStatus?("尝试默认密码...") }
            for i in 0..<foundResults.count {
                guard !cancelled else { break }
                for cred in foundResults[i].brand.creds {
                    let parts = cred.split(separator: ":")
                    guard parts.count == 2 else { continue }
                    let user = String(parts[0]), pass = String(parts[1])
                    if await Self.tryLogin(host: foundResults[i].ip, port: foundResults[i].port, user: user, pass: pass) {
                        foundResults[i].workingCred = cred
                        await MainActor.run { self.onResult?(foundResults[i]) }
                        break
                    }
                }
            }

            let online = foundResults.filter(\.reachable).count
            let cracked = foundResults.filter { $0.workingCred != nil }.count
            await MainActor.run {
                self.onStatus?("完成: \(online) 在线, \(cracked) 可登录")
                self.onComplete?()
            }
        }
    }

    func stop() { cancelled = true }

    // MARK: - Internal

    private nonisolated func scanOne(ip: String, port: UInt16) async -> ScanResult? {
        guard await tcpConnect(host: ip, port: port) else { return nil }

        guard let (html, headers) = await httpGet(host: ip, port: port) else {
            return ScanResult(ip: ip, port: port, brand: Brand.all.last!, title: "(非HTTP)", server: "", reachable: true)
        }

        let server = headers["Server"] ?? ""
        let title = extractTitle(html)
        let matched = Brand.all.first { $0.match(html: html, server: server) } ?? Brand.all.last!
        return ScanResult(ip: ip, port: port, brand: matched, title: title, server: server, reachable: true)
    }

    private nonisolated func tcpConnect(host: String, port: UInt16) async -> Bool {
        await withCheckedContinuation { cont in
            let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            var done = false
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.cancel()
                    if !done { done = true; cont.resume(returning: true) }
                case .failed, .cancelled:
                    if !done { done = true; cont.resume(returning: false) }
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                conn.cancel()
                if !done { done = true; cont.resume(returning: false) }
            }
        }
    }

    private nonisolated func httpGet(host: String, port: UInt16) async -> (String, [String: String])? {
        let scheme = port == 443 || port == 8443 ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(host):\(port)/") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let httpResp = resp as? HTTPURLResponse else { return nil }
        let headers = (httpResp.allHeaderFields as? [String: String]) ?? [:]
        let html = String(data: data, encoding: .utf8) ?? ""
        return (html, headers)
    }

    static nonisolated func tryLogin(host: String, port: UInt16, user: String, pass: String) async -> Bool {
        let scheme = port == 443 || port == 8443 ? "https" : "http"

        // Basic Auth
        if let url = URL(string: "\(scheme)://\(host):\(port)/") {
            var req = URLRequest(url: url, timeoutInterval: 5)
            let auth = Data("\(user):\(pass)".utf8).base64EncodedString()
            req.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
            if let (_, resp) = try? await URLSession.shared.data(for: req),
               let r = resp as? HTTPURLResponse, r.statusCode == 200 { return true }
        }

        // Form POST
        for path in ["/login.html", "/login.htm", "/admin/login", "/login.php", "/api/login"] {
            guard let url = URL(string: "\(scheme)://\(host):\(port)\(path)") else { continue }
            var req = URLRequest(url: url, timeoutInterval: 5)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = "username=\(user)&password=\(pass)".data(using: .utf8)
            if let (_, resp) = try? await URLSession.shared.data(for: req),
               let r = resp as? HTTPURLResponse, r.statusCode == 200 || r.statusCode == 302 { return true }
        }
        return false
    }

    private func extractTitle(_ html: String) -> String {
        guard let s = html.range(of: "<title>"), let e = html.range(of: "</title>") else { return "" }
        return String(html[s.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func getWiFiInfo() -> WiFiInfo {
        var localIP: String? = nil, subnetMask: String? = nil
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0 else { return WiFiInfo(ssid: nil, localIP: nil, subnetMask: nil) }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let name = ptr?.pointee.ifa_name, String(cString: name) == "en0" else { continue }
            if let addr = ptr?.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                var mask = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                localIP = String(cString: host)
                if let netmask = ptr?.pointee.ifa_netmask {
                    getnameinfo(netmask, socklen_t(netmask.pointee.sa_len), &mask, socklen_t(mask.count), nil, 0, NI_NUMERICHOST)
                    subnetMask = String(cString: mask)
                }
            }
        }
        return WiFiInfo(ssid: nil, localIP: localIP, subnetMask: subnetMask)
    }
}

actor AsyncSemaphore {
    private let limit: Int
    private var count = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { self.limit = limit }
    func wait() async { if count < limit { count += 1; return }; await withCheckedContinuation { waiters.append($0) } }
    func signal() { count -= 1; if !waiters.isEmpty { waiters.removeFirst().resume(); count += 1 } }
}
