//
//  KeychainHelper.swift
//  OpenfortSwift
//
//  Created by Pavel Gurkovskii on 2025-07-16.
//

import Foundation
import Security

public enum OFKeychainHelper {
    
    @discardableResult
    public static func save(_ value: String, for key: String) -> OSStatus {
        guard let data = value.data(using: .utf8) else { return errSecParam }

        // Delete any existing item
        delete(for: key)

        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrAccount as String : key,
            kSecValueData as String   : data
        ]

        return SecItemAdd(query as CFDictionary, nil)
    }

    /// Verifies the app can actually write and read the Keychain. Returns `errSecSuccess` when
    /// usable; otherwise the failing `OSStatus` (commonly `errSecMissingEntitlement`, -34018, for
    /// an unsigned / entitlement-less app). The SDK stores all session state in the Keychain, so
    /// this is checked up front to fail with an actionable message instead of an opaque one.
    public static func accessibilityStatus() -> OSStatus {
        let probeKey = "openfort.keychain.accessibility.probe"
        let addStatus = save("ok", for: probeKey)
        guard addStatus == errSecSuccess else { return addStatus }

        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrAccount as String : probeKey,
            kSecReturnData as String  : true,
            kSecMatchLimit as String  : kSecMatchLimitOne
        ]
        var result: AnyObject?
        let getStatus = SecItemCopyMatching(query as CFDictionary, &result)
        delete(for: probeKey)
        return getStatus
    }
    
    public static func retrieve(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrAccount as String : key,
            kSecReturnData as String  : true,
            kSecMatchLimit as String  : kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)?.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
        
        return nil
    }
    
    public static func delete(for key: String) {
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrAccount as String : key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    public static func clearAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword
        ]
        SecItemDelete(query as CFDictionary)
    }
}
