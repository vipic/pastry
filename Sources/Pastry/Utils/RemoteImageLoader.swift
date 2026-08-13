import Cocoa

// MARK: - 远程图片加载器
// 异步拉取 HTML 中引用的远程图片，NSCache 内存缓存
final class RemoteImageLoader {
    nonisolated(unsafe) static let shared = RemoteImageLoader()

    private let diagnosticsLog = PastryLogger(category: "remote-image")

    private let cache = NSCache<NSString, NSImage>()
    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 20 * 1024 * 1024  // 20 MB
    }

    /// 同步查缓存
    func cached(for urlString: String) -> NSImage? {
        cache.object(forKey: urlString as NSString)
    }

    /// 异步拉取（缓存命中直接回调，未命中网络请求）
    func load(urlString: String, completion: @escaping (NSImage?) -> Void) {
        guard NetworkAccessPolicy.isLinkPreviewEnabled else {
            completion(nil)
            return
        }

        let key = urlString as NSString
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }

        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        BoundedRemoteResourceLoader.shared.load(
            request: request,
            maxBytes: NetworkAccessPolicy.maxImageBytes
        ) { [weak self] data, response, error in
            guard let self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            guard NetworkAccessPolicy.responseWithinLimit(response, maxBytes: NetworkAccessPolicy.maxImageBytes),
                  let data = data,
                  data.count <= NetworkAccessPolicy.maxImageBytes,
                  error == nil,
                  let image = NSImage(data: data)
            else {
                let nsError = error as NSError?
                self.diagnosticsLog.warning(
                    "远程缩略图加载失败",
                    event: "remote_image.load.failed",
                    metadata: [
                        "status_code": String((response as? HTTPURLResponse)?.statusCode ?? -1),
                        "received_bytes": String(data?.count ?? 0),
                        "error_domain": nsError?.domain ?? "none",
                        "error_code": String(nsError?.code ?? 0)
                    ]
                )
                DispatchQueue.main.async { completion(nil) }
                return
            }
            // 缓存开销 = 数据字节数
            self.cache.setObject(image, forKey: key, cost: data.count)
            DispatchQueue.main.async { completion(image) }
        }
    }
}
