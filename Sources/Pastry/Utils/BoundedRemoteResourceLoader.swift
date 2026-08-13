import Foundation

struct BoundedDataAccumulator {
    private(set) var data = Data()
    let maxBytes: Int

    mutating func append(_ chunk: Data) -> Bool {
        guard chunk.count <= maxBytes, data.count <= maxBytes - chunk.count else { return false }
        data.append(chunk)
        return true
    }
}

/// 共享流式下载器：在接收过程中执行响应与重定向校验，并在超过上限时立即取消。
final class BoundedRemoteResourceLoader: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = BoundedRemoteResourceLoader()

    typealias Completion = (Data?, URLResponse?, Error?) -> Void

    private struct State {
        var accumulator: BoundedDataAccumulator
        var response: URLResponse?
        let completion: Completion

        init(maxBytes: Int, completion: @escaping Completion) {
            accumulator = BoundedDataAccumulator(maxBytes: maxBytes)
            self.completion = completion
        }
    }

    private final class ValidationWork: @unchecked Sendable {
        let request: URLRequest
        let maxBytes: Int
        let completion: Completion

        init(request: URLRequest, maxBytes: Int, completion: @escaping Completion) {
            self.request = request
            self.maxBytes = maxBytes
            self.completion = completion
        }
    }

    private let lock = NSLock()
    private var states: [Int: State] = [:]
    private let validationQueue = DispatchQueue(
        label: "com.nekutai.pastry.remote-resource-validation",
        qos: .utility,
        attributes: .concurrent
    )
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 10
        let queue = OperationQueue()
        queue.name = "com.nekutai.pastry.remote-resource"
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }()

    private override init() {}

    func load(
        request: URLRequest,
        maxBytes: Int,
        completion: @escaping Completion
    ) {
        let work = ValidationWork(request: request, maxBytes: maxBytes, completion: completion)
        validationQueue.async { [weak self] in
            self?.startValidated(work)
        }
    }

    private func startValidated(_ work: ValidationWork) {
        guard let url = work.request.url,
              NetworkAccessPolicy.isAllowedRemoteResourceURL(url)
        else {
            work.completion(nil, nil, URLError(.unsupportedURL))
            return
        }

        let task = session.dataTask(with: work.request)
        lock.withLock {
            states[task.taskIdentifier] = State(maxBytes: work.maxBytes, completion: work.completion)
        }
        task.resume()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, NetworkAccessPolicy.shouldFollowRedirect(to: url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let state = state(for: dataTask.taskIdentifier),
              NetworkAccessPolicy.responseWithinLimit(response, maxBytes: state.accumulator.maxBytes)
        else {
            completionHandler(.cancel)
            finish(taskID: dataTask.taskIdentifier, data: nil, response: response, error: URLError(.dataLengthExceedsMaximum))
            return
        }
        lock.withLock {
            states[dataTask.taskIdentifier]?.response = response
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let exceeded = lock.withLock { () -> Bool in
            guard var state = states[dataTask.taskIdentifier] else { return false }
            guard state.accumulator.append(data) else { return true }
            states[dataTask.taskIdentifier] = state
            return false
        }
        if exceeded {
            dataTask.cancel()
            finish(
                taskID: dataTask.taskIdentifier,
                data: nil,
                response: dataTask.response,
                error: URLError(.dataLengthExceedsMaximum)
            )
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let state = removeState(for: task.taskIdentifier) else { return }
        state.completion(error == nil ? state.accumulator.data : nil, state.response, error)
    }

    private func state(for taskID: Int) -> State? {
        lock.withLock { states[taskID] }
    }

    private func removeState(for taskID: Int) -> State? {
        lock.withLock { states.removeValue(forKey: taskID) }
    }

    private func finish(taskID: Int, data: Data?, response: URLResponse?, error: Error?) {
        guard let state = removeState(for: taskID) else { return }
        state.completion(data, response, error)
    }
}
