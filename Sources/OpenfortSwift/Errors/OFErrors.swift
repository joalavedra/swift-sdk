//
//  OFErrors.swift
//  OpenfortSwift
//
//  Created by Pavlo Hurkovskyi on 2025-07-25.
//

import Foundation

public enum OFError: Error, LocalizedError {
    case encodingFailed
    /// The app cannot read/write the iOS Keychain. `status` is the failing `OSStatus`
    /// (commonly `errSecMissingEntitlement`, -34018, for an unsigned or entitlement-less app).
    case keychainInaccessible(status: OSStatus)
    /// `OFConfig.plist` is missing, unreadable, or missing required keys.
    case missingConfiguration(String)
    /// The SDK's WebView bridge did not finish loading in time, or failed to load.
    case notReady(String)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Encoding failed"
        case .keychainInaccessible(let status):
            return """
            Keychain is not accessible (OSStatus \(status)). The Openfort SDK stores session \
            state in the iOS Keychain, so the app must be able to use it. Add the "Keychain \
            Sharing" capability (or otherwise sign the app with a keychain-access-groups \
            entitlement). On the iOS Simulator, run a signed build rather than an unsigned one.
            """
        case .missingConfiguration(let detail):
            return "Openfort configuration error: \(detail)"
        case .notReady(let detail):
            return "Openfort SDK is not ready: \(detail)"
        }
    }
}
