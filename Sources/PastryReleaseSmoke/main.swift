import AppKit
import Foundation

let arguments = CommandLine.arguments
guard let bundleIdentifier = argumentValue(after: "--bundle-id"),
      let pidText = argumentValue(after: "--pid"),
      let processIdentifier = pid_t(pidText),
      let application = NSRunningApplication(processIdentifier: processIdentifier) else {
    fputs("用法：PastryReleaseSmoke --bundle-id <id> --pid <pid>\n", stderr)
    exit(1)
}

guard waitForLaunch(application, timeout: 20) else {
    fputs("Pastry 正式进程未在时限内完成启动。\n", stderr)
    exit(1)
}
guard application.bundleIdentifier == bundleIdentifier else {
    fputs("正式应用 bundle id 不匹配。\n", stderr)
    exit(1)
}
guard application.activationPolicy == .accessory else {
    fputs("正式应用未以菜单栏 accessory 策略运行。\n", stderr)
    exit(1)
}
guard let icon = application.icon, icon.size.width > 0, icon.size.height > 0 else {
    fputs("正式应用未加载应用图标。\n", stderr)
    exit(1)
}

print(
    "正式应用验收通过：进程完成启动，bundle id 正确，" +
    "激活策略为 accessory，图标尺寸为 \(Int(icon.size.width))×\(Int(icon.size.height))。"
)

private func argumentValue(after option: String) -> String? {
    guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

private func waitForLaunch(_ application: NSRunningApplication, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if application.isTerminated { return false }
        if application.isFinishedLaunching { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    } while Date() < deadline
    return false
}
