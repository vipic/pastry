import XCTest
import Foundation
@testable import Pastry

final class BoundedRemoteResourceLoaderTests: XCTestCase {
    private func load(_ path: String, maxBytes: Int = 5) async -> (Data?, URLResponse?, Error?) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResourceProtocol.self]
        let loader = BoundedRemoteResourceLoader(configuration: configuration)
        defer { loader.invalidateAndCancel() }
        let complete = expectation(description: "完成且仅完成一次")
        complete.assertForOverFulfill = true
        let result = ResourceResult()
        loader.load(request: URLRequest(url: URL(string: "https://8.8.8.8\(path)")!), maxBytes: maxBytes) { data, response, error in
            result.set(data, response, error)
            complete.fulfill()
        }
        await fulfillment(of: [complete], timeout: 3)
        return result.value
    }

    func testLoaderAcceptsResponseExactlyAtByteLimit() async {
        let (data, response, error) = await load("/ok")
        XCTAssertEqual(data, Data([1, 2, 3, 4, 5]))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNil(error)
    }

    func testLoaderRejectsDeclaredOversizeBeforeReturningContent() async {
        let (data, _, error) = await load("/oversized")
        XCTAssertNil(data)
        XCTAssertEqual((error as? URLError)?.code, .dataLengthExceedsMaximum)
    }

    func testLoaderRejectsStreamThatExceedsLimitWithoutContentLength() async {
        let (data, _, error) = await load("/chunked")
        XCTAssertNil(data)
        XCTAssertEqual((error as? URLError)?.code, .dataLengthExceedsMaximum)
    }

    func testLoaderPreservesTransportFailureInsteadOfReturningPartialData() async {
        let (data, _, error) = await load("/failed")
        XCTAssertNil(data)
        XCTAssertEqual((error as? URLError)?.code, .timedOut)
    }

    func testLoaderRejectsPrivateInitialURLWithoutStartingNetwork() async {
        let complete = expectation(description: "拒绝私网地址")
        BoundedRemoteResourceLoader.shared.load(request: URLRequest(url: URL(string: "https://127.0.0.1/private")!), maxBytes: 5) { data, response, error in
            XCTAssertNil(data)
            XCTAssertNil(response)
            XCTAssertEqual((error as? URLError)?.code, .unsupportedURL)
            complete.fulfill()
        }
        await fulfillment(of: [complete], timeout: 3)
    }

    func testRedirectDelegateRejectsPrivateTargetAndAllowsPublicTarget() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let response = HTTPURLResponse(url: URL(string: "https://8.8.8.8/start")!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let task = session.dataTask(with: response.url!) // 不 resume，不访问网络。
        for (raw, allowed) in [("https://127.0.0.1/private", false), ("https://8.8.8.8/public", true)] {
            let request = URLRequest(url: URL(string: raw)!)
            BoundedRemoteResourceLoader.shared.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) { next in
                XCTAssertEqual(next?.url, allowed ? request.url : nil)
            }
        }
    }

    func testAccumulatorAcceptsChunksUpToLimit() {
        var accumulator = BoundedDataAccumulator(maxBytes: 5)

        XCTAssertTrue(accumulator.append(Data([1, 2])))
        XCTAssertTrue(accumulator.append(Data([3, 4, 5])))
        XCTAssertEqual(accumulator.data, Data([1, 2, 3, 4, 5]))
    }

    func testAccumulatorRejectsChunkBeforeBufferExceedsLimit() {
        var accumulator = BoundedDataAccumulator(maxBytes: 4)

        XCTAssertTrue(accumulator.append(Data([1, 2, 3])))
        XCTAssertFalse(accumulator.append(Data([4, 5])))
        XCTAssertEqual(accumulator.data, Data([1, 2, 3]))
    }
}

private final class ResourceResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: (Data?, URLResponse?, Error?) = (nil, nil, nil)
    func set(_ data: Data?, _ response: URLResponse?, _ error: Error?) {
        lock.withLock { stored = (data, response, error) }
    }
    var value: (Data?, URLResponse?, Error?) { lock.withLock { stored } }
}

private final class ResourceProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let headers = path == "/chunked" ? [:] : ["Content-Length": path == "/oversized" ? "6" : "5"]
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([1, 2, 3]))
        if path == "/failed" {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
        } else {
            client?.urlProtocol(self, didLoad: path == "/chunked" ? Data([4, 5, 6]) : Data([4, 5]))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
