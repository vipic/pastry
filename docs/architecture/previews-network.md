# 预览与网络资源架构

> 源码核对：2026-09-03，基线 `a5691d8`。静态核对；不表示已验证所有远端网站或系统 Quick Look 行为。

## 职责与入口

卡片从历史记录生成网页摘要、远程缩略图及用户主动打开的 Quick Look 预览。采集和数据库属于[剪贴板模块](clipboard-history.md)，预览关闭后的焦点交接属于[浮层模块](overlay.md)。

源码入口：[LinkPreviewLoader](../../Sources/Pastry/UI/LinkPreviewLoader.swift)、[RemoteImageLoader](../../Sources/Pastry/Utils/RemoteImageLoader.swift)、[RemoteThumbnail](../../Sources/Pastry/UI/RemoteThumbnail.swift)、[BoundedRemoteResourceLoader](../../Sources/Pastry/Utils/BoundedRemoteResourceLoader.swift)、[NetworkAccessPolicy](../../Sources/Pastry/Utils/NetworkAccessPolicy.swift)、[ClipboardItemPreviewBuilder](../../Sources/Pastry/UI/ClipboardItemPreviewBuilder.swift)、[QLPreviewHelper](../../Sources/Pastry/UI/QuickLookPreviewHelper.swift)。

## 网页与缩略图流程

1. `LinkPreviewLoader.load` 先检查默认关闭的网络预览开关，再查 URL 对应的内存缓存。
2. 缓存未命中时经共享流式下载器获取 HTML。标题依次取 `og:title`、`title`、`og:site_name`；描述取 `og:description`。
3. 图片依次尝试 Open Graph / Twitter / itemprop 元数据、`link` 图片声明、前 30 个 `img` 的语义评分。评分降低 logo、icon、avatar 的权重，而不是一律过滤；候选全部过滤后取第一个可解析图片，并非“最大的图片”。
4. 图片源支持 lazy 属性和 srcset；相对路径以请求页面 URL 解析，HTTP 图源升级为 HTTPS，但最终仍需网络策略放行。
5. `RemoteImageLoader` 下载、解码并缓存图片，`RemoteThumbnail` 管理视图请求状态和自己的缓存。网页摘要、图片加载器和缩略图视图有不同的 NSCache，不能当成统一的持久缓存。

卡片未得到摘要或图片时使用当前内容视图的占位状态；不要依赖旧 AGENTS 中“统一使用 redacted 骨架屏”的描述。缓存命中与异步下载的回调路径不同，调用方更新 UI 时需确认线程。

## 网络边界

- `NetworkAccessPolicy` 检查 HTTPS、主机字面量和 DNS 解析地址。localhost、`.local` 及代码列出的内网、链路本地等地址受到限制，DNS 失败时拒绝请求。
- 初始请求、每次重定向和最终响应都检查策略；只接受 2xx 响应。
- HTML 上限为 2,000,000 字节，图片为 5,000,000 字节。下载器在累积数据超过上限时立即取消，而非只信任 Content-Length。
- DNS 字面量检查与解析结果检查不是同一规则集；解析结果允许部分本地代理 fake-IP 地址。修改时需同时检查两个分支。

## Quick Look

`ClipboardItemPreviewBuilder` 为键盘 Space 和卡片动作构造同一种元数据。多文件不支持该预览，单文件和图片需存在于磁盘；文本类可生成临时文件，图片优先用原图。`QLPreviewHelper` 用 NSPopover 承载 QLPreviewView，并在关闭后通知浮层恢复 key。

## 已知边界与待验证

- DNS 预检查与 URLSession 建立连接是分开的，没有固定实际连接 IP，不能把当前逻辑描述为彻底消除了 DNS 重绑定风险。
- 网络开关控制这里的自动加载器，不等于清除已有内存缓存，也不覆盖用户主动交给系统 Quick Look 的 URL。
- HTML 元数据提取不是浏览器，不执行页面 JavaScript；相对图片以原请求 URL 解析，重定向后的页面可能需要额外适配。
- 临时预览文件和系统预览行为需在相关改动时实际检查；单元测试不等于隐私或网络安全的全面验收。

## 验证

重点参考 [LinkPreviewLoaderTests](../../Tests/PastryTests/LinkPreviewLoaderTests.swift)、[NetworkAccessPolicyTests](../../Tests/PastryTests/NetworkAccessPolicyTests.swift)、[BoundedRemoteResourceLoaderTests](../../Tests/PastryTests/BoundedRemoteResourceLoaderTests.swift) 和 [ClipboardItemPreviewBuilderTests](../../Tests/PastryTests/ClipboardItemPreviewBuilderTests.swift)。命令及人工验证边界见[测试说明](../TESTING.md)。
