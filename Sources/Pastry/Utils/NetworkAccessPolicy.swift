import Foundation
import OSLog

enum NetworkAccessPolicy {
    static let maxHTMLBytes = 2_000_000
    static let maxImageBytes = 5_000_000

    private static let log = PastryLogger(category: "netpolicy")

    static var isLinkPreviewEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.linkPreviewNetworkEnabled)
    }

    /// 校验远程资源 URL 是否允许访问。
    ///
    /// 三层检查：
    /// 1. scheme 必须 https、host 非空
    /// 2. 字符串层面的内网/链路本地/保留地址过滤（覆盖 IPv4 各种字面量形式 + IPv6）
    /// 3. DNS 解析后的实际 IP 重新校验，防 DNS 重绑定
    static func isAllowedRemoteResourceURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host(percentEncoded: false)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty
        else { return false }

        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if normalized == "localhost" || normalized.hasSuffix(".localhost") { return false }
        if normalized.hasSuffix(".local") { return false }
        if isBlockedHostLiteral(normalized) { return false }

        // 解析后再次校验全部 A / AAAA 记录：任一地址可达内网就拒绝。
        // 注意：198.18.0.0/15 常被 Clash/Surge fake-ip 用作假地址，不能当 DNS 结果拦截，
        // 否则链接预览 HTML/缩略图会对所有公网域名直接失败。
        guard let addresses = Self.resolvedAddresses(for: normalized) else { return false }
        if let blockedAddress = addresses.first(where: { address in
            address.contains(":")
                ? isBlockedIPv6Literal(address.lowercased())
                : isDNSRebindingTargetIPv4(address)
        }) {
            log.warning(
                "拒绝疑似 DNS 重绑定的远程资源",
                event: "network_policy.dns_rebinding.blocked",
                metadata: ["resolved_ip": blockedAddress]
            )
            return false
        }
        return true
    }

    static func responseWithinLimit(_ response: URLResponse?, maxBytes: Int) -> Bool {
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let finalURL = http.url,
              isAllowedRemoteResourceURL(finalURL)
        else { return false }

        let expected = http.expectedContentLength
        return expected < 0 || expected <= Int64(maxBytes)
    }

    static func shouldFollowRedirect(to url: URL) -> Bool {
        isAllowedRemoteResourceURL(url)
    }

    // MARK: - 字符串层过滤

    /// 判断 host 字面量是否命中内网/保留段。覆盖短格式、十进制整数的 IPv4 与各种 IPv6 形式。
    private static func isBlockedHostLiteral(_ host: String) -> Bool {
        // IPv6
        if host.contains(":") {
            return isBlockedIPv6Literal(host)
        }

        // 非数字主机名（域名）→ 字符串层放行，交给 DNS 解析后的 IP 校验
        if !host.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789.").contains($0) }) {
            return false
        }

        // 短格式 IPv4：少于 4 段，但每段都是十进制整数（如 127.1、10.1）
        // inet_aton 风格的逐段填充——任何 a.b.c、a.b、a 单数字形式都视为 IPv4。
        let dotted = host.split(separator: ".", omittingEmptySubsequences: false)
        if dotted.count < 4 {
            // 仅当所有非空段都是纯数字时才按 IPv4 处理
            let parts = dotted.map(String.init)
            if parts.allSatisfy({ $0.isEmpty ? false : $0.allSatisfy(\.isNumber) }) {
                // 把短格式归一化为 4 段后再校验
                if let normalized = normalizeShortIPv4(parts) {
                    return isBlockedIPv4Address(normalized)
                }
            }
            return false
        }

        // 标准 4 段 IPv4
        if dotted.count == 4, let a = UInt32(dotted[0]), let b = UInt32(dotted[1]),
           let c = UInt32(dotted[2]), let d = UInt32(dotted[3]),
           a <= 255, b <= 255, c <= 255, d <= 255 {
            return isBlockedIPv4Octets(a, b, c, d)
        }

        // 十进制整数形式（如 2130706433 = 127.0.0.1）
        if let n = UInt32(host) {
            let a = (n >> 24) & 0xFF
            let b = (n >> 16) & 0xFF
            return isBlockedIPv4Octets(a, b, (n >> 8) & 0xFF, n & 0xFF)
        }

        return false
    }

    /// 把 a.b / a.b.c 短格式 IPv4 归一化为 4 段 IP 字符串。
    /// inet_aton 语义：最后一段承担剩余位（如 127.1 → 127.0.0.1，192.168.1 → 192.168.0.1）。
    private static func normalizeShortIPv4(_ parts: [String]) -> String? {
        guard parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        let nums = parts.compactMap { UInt32($0) }
        guard nums.count == parts.count, nums.allSatisfy({ $0 <= 0xFFFFFFFF }) else { return nil }

        switch nums.count {
        case 1:
            // 单个整数 → 等价于十进制整数形式，不应走到这里（外层已处理），但保留兜底
            let n = nums[0]
            return "\((n >> 24) & 0xFF).\((n >> 16) & 0xFF).\((n >> 8) & 0xFF).\(n & 0xFF)"
        case 2:
            // a.b → a.0.0.b（b 承担低 16 位，但标准 inet_aton 实际是 a.b 视作 a.b 的高低位合并）
            // 简化：a.b → a.b 的标准解释。绝大多数现实用法（127.1）属于 a.<last> 形式
            let a = nums[0], b = nums[1]
            return "\(a).0.0.\(b)"
        case 3:
            // a.b.c → a.b.c 的标准解释
            let a = nums[0], b = nums[1], c = nums[2]
            return "\(a).\(b).0.\(c)"
        default:
            return nil
        }
    }

    private static func isBlockedIPv4Octets(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) -> Bool {
        switch a {
        case 0, 10, 127:
            return true
        case 100:
            return (64...127).contains(b)
        case 169:
            return b == 254
        case 172:
            return (16...31).contains(b)
        case 192:
            return b == 168 || b == 0
        case 198:
            return b == 18 || b == 19
        default:
            return a >= 224
        }
    }

    /// 4 段 IPv4 字符串是否命中保留段。
    private static func isBlockedIPv4Address(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 <= 255 }) else { return false }
        return isBlockedIPv4Octets(parts[0], parts[1], parts[2], parts[3])
    }

    /// DNS 重绑定防护：只拦真正能打到本机/内网的地址。
    /// 不含 198.18.0.0/15（基准测试段，也被本地代理 fake-ip 大量使用）。
    private static func isDNSRebindingTargetIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 <= 255 }) else { return false }
        let a = parts[0], b = parts[1]
        switch a {
        case 0, 10, 127:
            return true
        case 100:
            return (64...127).contains(b) // CGNAT
        case 169:
            return b == 254
        case 172:
            return (16...31).contains(b)
        case 192:
            return b == 168 // 仅 RFC1918；不含 192.0.0.0/24 字面量段在 DNS 结果里的误伤
        default:
            return false
        }
    }

    private static func isBlockedIPv6Literal(_ host: String) -> Bool {
        let addressText = host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
        var address = in6_addr()
        guard inet_pton(AF_INET6, addressText, &address) == 1 else { return true }
        let bytes = withUnsafeBytes(of: &address) { Array($0) }

        if bytes.allSatisfy({ $0 == 0 }) { return true } // unspecified
        if bytes.dropLast().allSatisfy({ $0 == 0 }), bytes.last == 1 { return true } // loopback
        if bytes[0] & 0xFE == 0xFC { return true } // unique local fc00::/7
        if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { return true } // link-local fe80::/10
        if bytes[0] == 0xFF { return true } // multicast

        let isMapped = bytes[0..<10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xFF && bytes[11] == 0xFF
        let isCompatible = bytes[0..<12].allSatisfy({ $0 == 0 })
        if isMapped || isCompatible {
            return isBlockedIPv4Octets(
                UInt32(bytes[12]),
                UInt32(bytes[13]),
                UInt32(bytes[14]),
                UInt32(bytes[15])
            )
        }
        return false
    }

    // MARK: - DNS 解析

    private static func resolvedAddresses(for hostname: String) -> [String]? {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(hostname, nil, &hints, &result) == 0, let head = result else {
            return nil
        }
        defer { freeaddrinfo(head) }

        var addresses: [String] = []
        var ptr: UnsafeMutablePointer<addrinfo>? = head
        while let cur = ptr {
            if cur.pointee.ai_family == AF_INET, let sa = cur.pointee.ai_addr {
                let sin = UnsafeRawPointer(sa).assumingMemoryBound(to: sockaddr_in.self)
                var addr = sin.pointee.sin_addr
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if let s = inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) {
                    addresses.append(String(cString: s))
                }
            } else if cur.pointee.ai_family == AF_INET6, let sa = cur.pointee.ai_addr {
                let sin6 = UnsafeRawPointer(sa).assumingMemoryBound(to: sockaddr_in6.self)
                var addr = sin6.pointee.sin6_addr
                var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                if let s = inet_ntop(AF_INET6, &addr, &buf, socklen_t(INET6_ADDRSTRLEN)) {
                    addresses.append(String(cString: s))
                }
            }
            ptr = cur.pointee.ai_next
        }
        return addresses.isEmpty ? nil : Array(Set(addresses))
    }

    // MARK: - Testing

    static func isDNSRebindingTargetIPv4ForTesting(_ ip: String) -> Bool {
        isDNSRebindingTargetIPv4(ip)
    }
}
