//
//  KeychainManager.swift
//  LanguageFlow
//

import Foundation
import Security

class KeychainManager {
    private static let service = "com.languageflow.deviceid"
    private static let account = "device_uuid"
    private static let tokenAccount = "access_token"

    // MARK: - Device UUID Management
    static func getOrCreateDeviceUUID() -> String {
        if let existingUUID = getDeviceUUID() {
            print("[Info] Found existing device UUID: \(existingUUID)")
            return existingUUID
        }
        let newUUID = UUID().uuidString
        saveDeviceUUID(newUUID)
        print("[Info] Generated new device UUID: \(newUUID)")
        return newUUID
    }

    private static func getDeviceUUID() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let uuid = String(data: data, encoding: .utf8) else {
            return nil
        }
        return uuid
    }

    private static func saveDeviceUUID(_ uuid: String) {
        guard let data = uuid.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[error] Device UUID save failed: \(status)")
        } else {
            print("[Info] Device UUID saved to Keychain")
        }
    }

    // MARK: - Access Token Management
    static func saveToken(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[error] Token save failed: \(status)")
        } else {
            print("[Info] Token saved to Keychain")
        }
    }

    static func getToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    #if DEBUG
    static func deleteDeviceUUID() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            print("[Info] UUID deleted from Keychain")
        }
    }

    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount
        ]
        SecItemDelete(query as CFDictionary)
        print("[Info] Token deleted from Keychain")
    }
    #endif
}
