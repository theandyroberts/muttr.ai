import Foundation
@preconcurrency import KeychainAccess

final class KeychainService: Sendable {
    private let keychain: Keychain

    init() {
        self.keychain = Keychain(service: AppConstants.Keychain.serviceName)
    }

    func getOpenAIKey() -> String? {
        try? keychain.get(AppConstants.Keychain.openAIKeyAccount)
    }

    func setOpenAIKey(_ key: String) throws {
        try keychain.set(key, key: AppConstants.Keychain.openAIKeyAccount)
    }

    func removeOpenAIKey() throws {
        try keychain.remove(AppConstants.Keychain.openAIKeyAccount)
    }

    func getAnthropicKey() -> String? {
        try? keychain.get(AppConstants.Keychain.anthropicKeyAccount)
    }

    func setAnthropicKey(_ key: String) throws {
        try keychain.set(key, key: AppConstants.Keychain.anthropicKeyAccount)
    }

    func removeAnthropicKey() throws {
        try keychain.remove(AppConstants.Keychain.anthropicKeyAccount)
    }
}
