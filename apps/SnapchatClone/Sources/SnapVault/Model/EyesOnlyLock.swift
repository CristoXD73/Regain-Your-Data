import CryptoKit
import Foundation
import LocalAuthentication
import Observation
import Security

/// My Eyes Only: a 4-digit passcode (only a salted, stretched hash is kept, in a private file in
/// Application Support), or Touch ID / Apple Watch. Forgetting the passcode is fixed with the Mac's
/// own password.
///
/// Earlier versions kept the hash in the login Keychain. Because the app is signed locally, every
/// rebuild counted as a new app and macOS asked for the Keychain password on each launch. The hash
/// is now a file; the old Keychain item is read once (when My Eyes Only is first opened), moved,
/// and deleted.
@MainActor
@Observable
final class EyesOnlyLock {
    enum State: Equatable { case needsSetup, locked, unlocked }

    private(set) var state: State
    private(set) var failedAttempts = 0
    private(set) var coolDownUntil: Date?
    var message: String?

    init() {
        // A plain file check: no Keychain access at launch.
        state = Self.readFile() != nil ? .locked : .needsSetup
    }

    /// Moves a passcode saved by an earlier version out of the Keychain. Runs at most once, and
    /// only when My Eyes Only is opened, so any Keychain prompt appears in context.
    func migrateFromKeychainIfNeeded() {
        let flag = "eyesOnlyKeychainMigrated"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        guard Self.readFile() == nil, let old = Self.readKeychain(), old.count == 48 else { return }
        Self.writeFile(old)
        Self.deleteKeychain()
        state = .locked
    }

    var biometricsAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometricsOrWatch, error: nil)
    }

    func lock() { if state == .unlocked { state = .locked } }

    // MARK: Passcode

    func setPasscode(_ code: String) {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        Self.writeFile(salt + Self.stretch(code, salt: salt))
        failedAttempts = 0
        state = .unlocked
    }

    /// Returns true when the code is right. Five wrong tries in a row pause entry for 30 seconds.
    func tryPasscode(_ code: String) -> Bool {
        if let until = coolDownUntil, until > Date() { return false }
        guard let stored = Self.readFile(), stored.count == 48 else { return false }
        let salt = stored.prefix(16), hash = stored.suffix(32)
        if Self.stretch(code, salt: salt) == hash {
            failedAttempts = 0
            coolDownUntil = nil
            message = nil
            state = .unlocked
            return true
        }
        failedAttempts += 1
        if failedAttempts >= 5 {
            coolDownUntil = Date().addingTimeInterval(30)
            failedAttempts = 0
            message = "Too many tries. Wait 30 seconds."
        } else {
            message = "Wrong passcode"
        }
        return false
    }

    func unlockWithBiometrics() async {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = ""
        if (try? await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometricsOrWatch, localizedReason: "open My Eyes Only")) == true {
            failedAttempts = 0
            message = nil
            state = .unlocked
        }
    }

    /// Forgot the passcode: prove it's you with the Mac's password, then pick a new one.
    func resetWithMacPassword() async {
        let ctx = LAContext()
        if (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "reset your My Eyes Only passcode")) == true {
            try? FileManager.default.removeItem(at: Self.file)
            message = nil
            state = .needsSetup
        }
    }

    // MARK: Hashing and storage

    /// SHA-256 applied 100,000 times over salt + code, so guessing 10,000 codes is slow.
    private static func stretch(_ code: String, salt: Data) -> Data {
        var d = Data(SHA256.hash(data: salt + Data(code.utf8)))
        for _ in 0..<100_000 { d = Data(SHA256.hash(data: d + salt)) }
        return d
    }

    private static var file: URL { Paths.support.appendingPathComponent("eyes-only.key") }

    private static func readFile() -> Data? { try? Data(contentsOf: file) }

    /// Only this user can read or write it.
    private static func writeFile(_ data: Data) {
        try? data.write(to: file, options: [.atomic, .completeFileProtection])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private static let service = "com.regainyourdata.SnapVault.eyes-only"

    private static func keychainQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "passcode"]
    }

    private static func readKeychain() -> Data? {
        var q = keychainQuery()
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    private static func deleteKeychain() { SecItemDelete(keychainQuery() as CFDictionary) }
}
