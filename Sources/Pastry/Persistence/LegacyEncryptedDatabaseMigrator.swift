import CryptoKit
import CSQLCipher
import Darwin
import Foundation
import IOKit
import OSLog

/// 将旧版本留下的 SQLCipher 数据库一次性转换为明文 SQLite。
///
/// 新安装不会创建密钥；迁移成功后会删除旧 `.key`。这个类型仅保留升级兼容能力。
struct LegacyEncryptedDatabaseMigrator {
    private let dbPath: String
    private let log: Logger
    private let diagnosticsLog = PastryLogger(category: "database-migration")

    init(dbPath: String, log: Logger) {
        self.dbPath = dbPath
        self.log = log
    }

    func migrateIfNeeded() {
        let fm = FileManager.default
        let keyPath = dbPath + ".key"
        guard fm.fileExists(atPath: dbPath), fm.fileExists(atPath: keyPath) else { return }

        if Self.isReadablePlaintextDatabase(at: dbPath) {
            try? fm.removeItem(atPath: keyPath)
            return
        }

        guard let key = readLegacyKey(at: keyPath) else {
            diagnosticsLog.critical(
                "旧数据库密钥不可读，保留原数据库",
                event: "database_migration.legacy_key_unreadable"
            )
            return
        }

        let plaintextPath = dbPath + ".plaintext-migrate"
        let encryptedBackupPath = dbPath + ".encrypted-backup"
        try? fm.removeItem(atPath: plaintextPath)
        try? fm.removeItem(atPath: encryptedBackupPath)

        guard exportPlaintext(to: plaintextPath, key: key),
              Self.isReadablePlaintextDatabase(at: plaintextPath)
        else {
            try? fm.removeItem(atPath: plaintextPath)
            diagnosticsLog.critical(
                "旧加密数据库转换失败，保留原数据库",
                event: "database_migration.decrypt.failed"
            )
            return
        }

        do {
            try fm.moveItem(atPath: dbPath, toPath: encryptedBackupPath)
            do {
                try fm.moveItem(atPath: plaintextPath, toPath: dbPath)
            } catch {
                try? fm.moveItem(atPath: encryptedBackupPath, toPath: dbPath)
                throw error
            }

            try? fm.removeItem(atPath: dbPath + "-wal")
            try? fm.removeItem(atPath: dbPath + "-shm")
            try? fm.removeItem(atPath: encryptedBackupPath)
            try? fm.removeItem(atPath: keyPath)
            log.info("旧加密数据库已转换为明文 SQLite")
            diagnosticsLog.notice(
                "旧加密数据库转换完成",
                event: "database_migration.decrypt.completed"
            )
        } catch {
            try? fm.removeItem(atPath: plaintextPath)
            diagnosticsLog.critical(
                "替换明文数据库失败",
                event: "database_migration.replace.failed",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    private func exportPlaintext(to plaintextPath: String, key: Data) -> Bool {
        var database: OpaquePointer?
        guard sqlite3_open(dbPath, &database) == SQLITE_OK, let database else { return false }
        defer { sqlite3_close(database) }

        let keyResult = key.withUnsafeBytes { bytes in
            sqlite3_key(database, bytes.baseAddress, Int32(key.count))
        }
        guard keyResult == SQLITE_OK, Self.isReadable(database) else { return false }

        _ = sqlite3_exec(database, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
        let escapedPath = plaintextPath.replacingOccurrences(of: "'", with: "''")
        guard sqlite3_exec(
            database,
            "ATTACH DATABASE '\(escapedPath)' AS plaintext KEY '';",
            nil,
            nil,
            nil
        ) == SQLITE_OK else { return false }
        defer { _ = sqlite3_exec(database, "DETACH DATABASE plaintext;", nil, nil, nil) }

        return sqlite3_exec(database, "SELECT sqlcipher_export('plaintext');", nil, nil, nil) == SQLITE_OK
    }

    private func readLegacyKey(at path: String) -> Data? {
        guard let sealed = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let key = try? AES.GCM.open(box, using: Self.legacyDeviceKEK())
        else { return nil }
        return Data(key)
    }

    private static func isReadablePlaintextDatabase(at path: String) -> Bool {
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else { return false }
        defer { sqlite3_close(database) }
        return isReadable(database)
    }

    private static func isReadable(_ database: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        return sqlite3_prepare_v2(database, "SELECT count(*) FROM sqlite_master;", -1, &statement, nil) == SQLITE_OK
            && sqlite3_step(statement) == SQLITE_ROW
    }

    private static func legacyDeviceKEK() -> SymmetricKey {
        let salt = Data("com.nekutai.pastry.kek".utf8)
        let material = Data(legacyDeviceIdentity().utf8)
        let info = Data("pastry-db-key".utf8)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: material),
            salt: salt,
            info: info,
            outputByteCount: 32
        )
    }

    private static func legacyDeviceIdentity() -> String {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        defer { if platformExpert != 0 { IOObjectRelease(platformExpert) } }
        guard platformExpert != 0,
              let uuid = IORegistryEntryCreateCFProperty(
                platformExpert,
                kIOPlatformUUIDKey as CFString,
                kCFAllocatorDefault,
                0
              )?.takeRetainedValue() as? String
        else { return "pastry-fallback-identity" }
        return uuid
    }

    static func writeLegacyKeyForTesting(_ key: Data, to path: String) throws {
        let box = try AES.GCM.seal(key, using: legacyDeviceKEK())
        guard let combined = box.combined else {
            throw CocoaError(.fileWriteUnknown)
        }
        try combined.write(to: URL(fileURLWithPath: path), options: .atomic)
        chmod(path, 0o600)
    }
}
