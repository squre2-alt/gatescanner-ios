import Foundation

struct Brand {
    let name: String
    let creds: [String]       // "user:pass"
    let paths: [String]       // login page paths
    let fingerprints: [String]

    static let all: [Brand] = [
        Brand(name: "大华 Dahua", creds: ["admin:admin","admin:admin123","admin:admin123456","888888:888888","666666:666666"], paths: ["/","/admin","/login.htm"], fingerprints: ["Dahua","大华","NetSurveillance"]),
        Brand(name: "海康 Hikvision", creds: ["admin:12345","admin:admin12345","admin:abcd1234"], paths: ["/","/admin","/login.asp"], fingerprints: ["Hikvision","海康","iVMS"]),
        Brand(name: "捷顺 Jieshun", creds: ["admin:admin","admin:123456","admin:888888","admin:jieshun123"], paths: ["/","/login.html","/admin/login"], fingerprints: ["捷顺","Jieshun","JSST"]),
        Brand(name: "科拓 KETO", creds: ["admin:admin","admin:123456","admin:keto123","admin:888888"], paths: ["/","/login.html"], fingerprints: ["科拓","KETO","keytop"]),
        Brand(name: "立方 Lifang", creds: ["admin:admin","admin:123456","admin:888888"], paths: ["/","/login.html"], fingerprints: ["立方","Lifang","reformer"]),
        Brand(name: "蓝卡 BlueCard", creds: ["admin:admin","admin:123456","admin:888888","admin:bluecard"], paths: ["/","/login.html"], fingerprints: ["蓝卡","BlueCard","bluecard"]),
        Brand(name: "富士智能 Fuji", creds: ["admin:admin","root:root","admin:123456","admin:fuji123"], paths: ["/","/login.htm"], fingerprints: ["富士","Fuji","fujica"]),
        Brand(name: "红门 Hongmen", creds: ["admin:admin","admin:123456","admin:888888","admin:hm123"], paths: ["/","/login.html"], fingerprints: ["红门","Hongmen"]),
        Brand(name: "道尔 Daoer", creds: ["admin:admin","admin:123456","admin:888888"], paths: ["/","/login.html"], fingerprints: ["道尔","Daoer","dorcon"]),
        Brand(name: "百胜 Baisheng", creds: ["admin:admin","admin:123456","admin:888888"], paths: ["/","/login.html"], fingerprints: ["百胜","Baisheng","bisen"]),
        Brand(name: "通用设备 Generic", creds: ["admin:admin","admin:123456","admin:password","admin:888888","root:root","root:admin","guest:guest"], paths: ["/","/login.html"], fingerprints: []),
    ]

    static let ports: [UInt16] = [80, 443, 8080, 8081, 8443, 8000, 8888, 37777]

    func match(html: String, server: String) -> Bool {
        if fingerprints.isEmpty { return true } // Generic matches anything
        let lower = html.lowercased() + server.lowercased()
        return fingerprints.contains { lower.contains($0.lowercased()) }
    }
}

struct ScanResult {
    let ip: String
    let port: UInt16
    let brand: Brand
    let title: String
    let server: String
    var workingCred: String?       // "user:pass"
    var reachable: Bool = false
}

struct WiFiInfo {
    let ssid: String?
    let localIP: String?
    let subnetMask: String?
    let gateway: String?

    var gateway: String? {
        guard let (net, _) = networkRange else { return nil }
        let gw = net + 1 // gateway is usually the first host in subnet
        let a = UInt8((gw >> 24) & 0xFF)
        let b = UInt8((gw >> 16) & 0xFF)
        let c = UInt8((gw >> 8) & 0xFF)
        let d = UInt8(gw & 0xFF)
        return "\(a).\(b).\(c).\(d)"
    }

    var networkRange: (UInt32, UInt32)? {
        guard let ip = localIP, let mask = subnetMask else { return nil }
        let ipParts = ip.split(separator: ".").compactMap { UInt8($0) }
        let maskParts = mask.split(separator: ".").compactMap { UInt8($0) }
        guard ipParts.count == 4, maskParts.count == 4 else { return nil }
        let ipInt = UInt32(ipParts[0])<<24 | UInt32(ipParts[1])<<16 | UInt32(ipParts[2])<<8 | UInt32(ipParts[3])
        let maskInt = UInt32(maskParts[0])<<24 | UInt32(maskParts[1])<<16 | UInt32(maskParts[2])<<8 | UInt32(maskParts[3])
        let net = ipInt & maskInt
        let broadcast = net | ~maskInt
        return (net, broadcast)
    }

    func ipArray() -> [String] {
        guard let (net, broad) = networkRange else { return [] }
        var ips: [String] = []
        for i in (net + 1)..<broad {
            let a = UInt8((i >> 24) & 0xFF)
            let b = UInt8((i >> 16) & 0xFF)
            let c = UInt8((i >> 8) & 0xFF)
            let d = UInt8(i & 0xFF)
            ips.append("\(a).\(b).\(c).\(d)")
        }
        return ips
    }
}
