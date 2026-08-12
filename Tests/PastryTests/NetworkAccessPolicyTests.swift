import XCTest
@testable import Pastry

final class NetworkAccessPolicyTests: XCTestCase {

    func testAllowsPublicHTTPSURL() {
        // 用 IP 字面量避开测试环境 DNS 劫持（某些 CI/代理会把 example.com 解析到 198.18.x）
        XCTAssertTrue(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://8.8.8.8/article")!))
    }

    func testRejectsHTTPURL() {
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "http://example.com/article")!))
    }

    func testRejectsLocalhost() {
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://localhost/test")!))
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://dev.localhost/test")!))
    }

    func testRejectsPrivateIPv4Ranges() {
        let blocked = [
            "https://10.0.0.1/a",
            "https://127.0.0.1/a",
            "https://169.254.1.1/a",
            "https://172.16.0.1/a",
            "https://172.31.255.255/a",
            "https://192.168.1.1/a",
            "https://100.64.0.1/a",
        ]
        for raw in blocked {
            XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: raw)!), raw)
        }
    }

    func testRejectsPrivateIPv6Ranges() {
        let blocked = [
            "https://[::1]/a",
            "https://[fe80::1]/a",
            "https://[fc00::1]/a",
            "https://[fd00::1]/a",
        ]
        for raw in blocked {
            XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: raw)!), raw)
        }
    }

    func testHTMLByteLimitAllowsLargeModernPages() {
        XCTAssertEqual(NetworkAccessPolicy.maxHTMLBytes, 2_000_000)
    }

    func testRejectsRedirectToPrivateAddress() {
        XCTAssertFalse(NetworkAccessPolicy.shouldFollowRedirect(to: URL(string: "https://127.0.0.1/admin")!))
        XCTAssertFalse(NetworkAccessPolicy.shouldFollowRedirect(to: URL(string: "https://192.168.1.1/admin")!))
    }

    func testResponseWithinLimitRejectsFinalPrivateURL() {
        let response = HTTPURLResponse(
            url: URL(string: "https://127.0.0.1/metadata")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Length": "128"]
        )

        XCTAssertFalse(NetworkAccessPolicy.responseWithinLimit(response, maxBytes: 1_000))
    }

    func testResponseWithinLimitRejectsOversizedContentLength() {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/page")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Length": "\(NetworkAccessPolicy.maxHTMLBytes + 1)"]
        )

        XCTAssertFalse(NetworkAccessPolicy.responseWithinLimit(response, maxBytes: NetworkAccessPolicy.maxHTMLBytes))
    }

    func testResponseWithinLimitAllowsPublicURLWithSmallBody() {
        let response = HTTPURLResponse(
            url: URL(string: "https://8.8.8.8/ok")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Length": "128"]
        )
        XCTAssertTrue(NetworkAccessPolicy.responseWithinLimit(response, maxBytes: 1_000))
    }

    func testResponseWithinLimitAllowsMissingContentLength() {
        let response = HTTPURLResponse(
            url: URL(string: "https://8.8.8.8/ok")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        XCTAssertTrue(NetworkAccessPolicy.responseWithinLimit(response, maxBytes: 1_000))
    }

    func testShouldFollowRedirectAllowsPublicHTTPS() {
        XCTAssertTrue(NetworkAccessPolicy.shouldFollowRedirect(to: URL(string: "https://8.8.8.8/next")!))
    }

    func testRejectsFileAndDataSchemes() {
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "file:///etc/passwd")!))
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "data:text/plain,hi")!))
    }

    // MARK: - 短格式 / 十进制 IPv4 / .local（SSRF 字面量）

    func testRejectsShortFormLoopbackIPv4() {
        // inet_aton 风格：127.1 → 127.0.0.1
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://127.1/a")!))
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://10.1/a")!))
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://192.168.1/a")!))
    }

    func testRejectsDecimalIntegerLoopback() {
        // 2130706433 == 127.0.0.1
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://2130706433/a")!))
        // 0 == 0.0.0.0
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://0/a")!))
    }

    func testRejectsMulticastAndReservedHighOctets() {
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://224.0.0.1/a")!))
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://255.255.255.255/a")!))
    }

    func testRejectsLinkLocalAndTestNet() {
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://169.254.10.20/a")!))
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://192.0.2.1/a")!)) // 192.0.0.0/24 via b==0
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://198.18.0.1/a")!))
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://198.19.1.1/a")!))
    }

    /// Clash/Surge fake-ip 会把公网域名解析到 198.18.x；DNS 重绑定检查不得因此拒绝缩略图请求。
    func testDNSRebindingIgnoresFakeIPBenchmarkRange() {
        XCTAssertFalse(
            NetworkAccessPolicy.isDNSRebindingTargetIPv4ForTesting("198.18.5.239"),
            "fake-ip 段不应视为 DNS 重绑定目标"
        )
        XCTAssertFalse(NetworkAccessPolicy.isDNSRebindingTargetIPv4ForTesting("198.19.1.1"))
        XCTAssertTrue(NetworkAccessPolicy.isDNSRebindingTargetIPv4ForTesting("127.0.0.1"))
        XCTAssertTrue(NetworkAccessPolicy.isDNSRebindingTargetIPv4ForTesting("10.0.0.1"))
        XCTAssertTrue(NetworkAccessPolicy.isDNSRebindingTargetIPv4ForTesting("192.168.1.1"))
        XCTAssertTrue(NetworkAccessPolicy.isDNSRebindingTargetIPv4ForTesting("172.16.0.1"))
        XCTAssertTrue(NetworkAccessPolicy.isDNSRebindingTargetIPv4ForTesting("169.254.1.1"))
        XCTAssertTrue(NetworkAccessPolicy.isDNSRebindingTargetIPv4ForTesting("100.64.0.1"))
    }

    /// 字面量 198.18 仍拒绝；但公网 hostname 即使被系统 DNS 指到 fake-ip 也应放行。
    func testAllowsPublicHostnameUnderFakeIPStyleDNS() {
        let url = URL(string: "https://www.apple.com/ac/structured-data/images/open_graph_logo.png")!
        XCTAssertTrue(
            NetworkAccessPolicy.isAllowedRemoteResourceURL(url),
            "公网 hostname 不得因 DNS 返回 198.18.x（代理 fake-ip）而被拒；否则链接预览图永久空白"
        )
    }

    func testRejectsMdnsLocalSuffix() {
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://printer.local/a")!))
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://foo.bar.local/")!))
    }

    func testRejectsIPv6MappedPrivate() {
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://[::ffff:127.0.0.1]/a")!))
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://[::ffff:192.168.0.1]/a")!))
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://[::192.168.1.1]/a")!))
    }

    func testRejectsExpandedIPv6Loopback() {
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://[0:0:0:0:0:0:0:1]/a")!))
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://[::ffff:7f00:1]/a")!))
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://[ff02::1]/a")!))
    }

    func testAllowsPublicIPv4Literal() {
        XCTAssertTrue(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://1.1.1.1/cdn-cgi")!))
        XCTAssertTrue(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://8.8.4.4/")!))
    }

    func testRejectsEmptyHostAndMissingScheme() {
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https:///path")!))
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "ftp://example.com/")!))
    }

    func testResponseWithinLimitRejectsNonSuccessStatus() {
        let response = HTTPURLResponse(
            url: URL(string: "https://8.8.8.8/ok")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: ["Content-Length": "10"]
        )
        XCTAssertFalse(NetworkAccessPolicy.responseWithinLimit(response, maxBytes: 1_000))
    }

    func testResponseWithinLimitRejectsNilResponse() {
        XCTAssertFalse(NetworkAccessPolicy.responseWithinLimit(nil, maxBytes: 1_000))
    }

    func testMaxImageBytesConstant() {
        XCTAssertEqual(NetworkAccessPolicy.maxImageBytes, 5_000_000)
    }
}
