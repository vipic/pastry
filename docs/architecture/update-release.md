# 更新与发布架构

> 源码核对：2026-09-03，基线 `a5691d8`。静态核对；本次未创建、安装或发布正式制品。

## 职责与入口

发布链把源码转成签名 App / DMG；应用内更新链获取 Release、下载 DMG、验证候选并替换当前 App。两条链通过版本、bundle ID 和签名身份连接，不应混用开发版与正式版身份。

源码入口：[UpdateChecker](../../Sources/Pastry/Utils/UpdateChecker.swift)、[UpdateInstallScriptBuilder](../../Sources/Pastry/Utils/UpdateInstallScriptBuilder.swift)、[AppDelegate](../../Sources/Pastry/PastryApp.swift)、[release.sh](../../release.sh)、[正式制品检查](../../scripts/verify_release.sh)、[DMG 冒烟](../../scripts/release_smoke.sh)。操作前置条件与命令见[发布流程](../RELEASE.md)。

## 更新数据流

1. `checkOutcome` 区分 skipped、failed、upToDate 和 updateAvailable。非强制检查受 24 小时间隔限制；开发构建默认跳过，明确允许时可检查。
2. 从 GitHub 获取近期 Release，缓存说明并比较版本；新版本必须有 DMG asset，不能把“没有 DMG”当成已是最新。
3. `StreamingDownloadDelegate` 经 ephemeral URLSession 将 HTTPS 数据流写入临时文件，按预计大小计算进度并执行字节上限。此下载器不是预览模块的 `BoundedRemoteResourceLoader`。
4. `applyUpdate` 把 DMG 移到稳定临时路径，在当前进程退出前挂载并预检候选 App 签名，拒绝签名验证失败或 ad-hoc 包。
5. `UpdateInstallScriptBuilder` 对外部路径做 shell quoting、限制版本字符串；helper 在退出后再次挂载，检查正式 bundle ID、预期版本、签名和身份连续性。读不到旧 App 的 designated requirement 时直接拒绝更新（fail-closed），不退化为「只校验签名有效性」。
6. helper 先移动旧 App 为备份，再复制候选；复制失败或安装后版本错误时执行恢复路径。成功后删除备份、卸载 DMG 并重启 App。DMG 卸载失败（卷被 Finder/Spotlight 占用）不中断重启，属于尽力而为的收尾。
7. helper 的日志与显式失败原因写在 App 自己的数据目录（`~/Library/Application Support/<AppName>/`），不是固定且世界可写的 `/tmp`；AppDelegate 下次启动读取错误文件（限制 2 KB）并展示。

## 发布链与不变量

- `mise run release -- <版本>` 经参数包装进入 `release.sh`；`publish` 在相同链路上增加远端操作。
- 正式制品生成前运行 `mise run check`，然后注入版本、编译、组装、签名、打包，并挂载最终 DMG 执行首次启动冒烟。Finder 布局窗口不激活，正式 bundle 通过 `open -g` 在后台启动；`release_smoke` 上下文禁止自动展示引导和更新错误窗口，避免发布链切换当前工作空间。
- 开发 bundle ID 为 `com.nekutai.pastry.dev`，正式版为 `com.nekutai.pastry`；证书默认 `Nekutai`，可显式配置自己的稳定证书。密钥不属于仓库内容。
- 发布要求 main 和干净工作区，版本 tag / Release 不静默覆盖。main 与 tag 使用原子推送；后续 Release 创建另有失败处理，不等于整个远端发布是单一事务。
- CI 运行统一检查，不持有正式签名私钥，不生成正式签名 DMG。

## 已知边界与待验证

- helper 现在要求必须读到旧 App 的 designated requirement，否则拒绝更新；代价是某些不产生 `designated =>` 输出的签名方式会让自动更新永久失败，这是显式接受的 fail-closed 取舍。
- `set -e` 下挂载、移动失败仍会直接退出：只有 DMG 卸载被显式降级为尽力而为。这类失败没有经过错误窗口，只留在 helper 日志里。
- 版本号白名单只接受 `x.y.z`（与 `release.sh` 的 tag 规则一致）。若远端出现 `v1.4.0-rc1` 这类预发布 tag，`checkOutcome` 仍会提示有更新，但 helper 会把版本回落成 `0.0.0` 并拒绝安装；发布预发布 tag 前需要先处理这条链路。
- 当前制品没有 notarization；签名校验不等于系统公证。
- 固定临时文件名、多进程并发更新和真实磁盘/权限故障未由这次静态核对全面验收。

## 验证

[UpdateCheckerTests](../../Tests/PastryTests/UpdateCheckerTests.swift)、[UpdateInstallScriptBuilderTests](../../Tests/PastryTests/UpdateInstallScriptBuilderTests.swift)、[SigningConfigurationTests](../../Tests/PastryTests/SigningConfigurationTests.swift) 与 [ReleaseWorkflowContractTests](../../Tests/PastryTests/ReleaseWorkflowContractTests.swift) 覆盖版本、脚本文本契约和签名配置；网络和最终制品测试按[测试说明](../TESTING.md)显式执行。不能仅凭脚本文本断言就宣称回滚已经过真实故障验证。
