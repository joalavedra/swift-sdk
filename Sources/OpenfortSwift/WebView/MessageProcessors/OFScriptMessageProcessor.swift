//
//  OFScriptMessageProcessor.swift
//  OpenfortSwift
//
//  Created by Pavlo Hurkovskyi on 2025-08-20.
//

import WebKit
import Foundation

@MainActor

internal final class OFScriptMessageProcessor {

    /// Method name pushed by the `__ofWatchEmbeddedState` JS hook whenever an openfort-js
    /// lifecycle event changes the embedded state. Carries the raw `OFEmbeddedState` Int.
    internal static let embeddedStateChanged = "embeddedStateChanged"

    private let jsonDecoder = JSONDecoder()
    private let storageMessageProcessor = OFStorageMessageProcessor()

    internal func process(_ message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any] else {
            print("Received message is not a dictionary: \(message.body)")
            return
        }

        if message.name == "secureHandler" {
            if storageMessageProcessor.processMessageForSecureStorage(message) {
                return
            }
        }

        guard let method = dict["method"] as? String else {
            print("No 'method' key in message: \(dict)")
            return
        }

        if storageMessageProcessor.processMessageForKeychain(message) {
            return
        }

        let success = dict["success"] as? Bool ?? false
        if success {
            if let handler = responseModelsDictionaryHandler[method] {
                handler(dict["data"], method)
            } else {
                decodeAndHandle(OFAuthResponse.self, from: dict["data"], method: method)
            }
        } else {
            handleError(dict, method: method)
        }
    }

    private var responseModelsDictionaryHandler: [String: (Any?, String) -> Void] {
        [
            OFMethods.logInWithEmailPassword: handlerFor(OFAuthResponse.self),
            OFMethods.signUpGuest: handlerFor(OFAuthResponse.self),
            OFMethods.signUpWithEmailPassword: handlerFor(OFAuthResponse.self),
            OFMethods.initOAuth: handlerFor(OFInitOAuthResponse.self),
            OFMethods.unlinkOAuth: handlerFor(OFUnlinkOAuthResponse.self),
            OFMethods.loginWithIdToken: handlerFor(OFAuthResponse.self),
            OFMethods.linkWallet: handlerFor(OFLinkWalletResponse.self),
            OFMethods.initLinkOAuth: handlerFor(OFInitLinkOAuthResponse.self),
            OFMethods.poolOAuth: handlerFor(OFPoolOAuthResponse.self),
            OFMethods.initSIWE: handlerFor(OFSIWEInitResponse.self),
            OFMethods.unlinkWallet: handlerFor(OFUnlinkWalletResponse.self),
            OFMethods.authenticateWithSIWE: handlerFor(OFAuthResponse.self),
            OFMethods.logInWithEmailOtp: handlerFor(OFAuthResponse.self),
            OFMethods.logInWithPhoneOtp: handlerFor(OFAuthResponse.self),
            OFMethods.linkPhoneOtp: handlerFor(OFAuthResponse.self),
            OFMethods.loginWithSiwe: handlerFor(OFAuthResponse.self),
            OFMethods.initLinkSiwe: handlerFor(OFSIWEInitResponse.self),
            OFMethods.linkWithSiwe: handlerFor(OFLinkWalletResponse.self),
            OFMethods.addEmail: handlerFor(OFAddEmailResponse.self),
            OFMethods.signTypedData: handlerFor(OFSignTypedDataResponse.self),
            OFMethods.get: handlerFor(OFEmbeddedAccount.self),
            OFMethods.getEthereumProvider: handlerFor(OFGetEthereumProviderResponse.self),
            OFMethods.configure: handlerFor(OFEmbeddedAccount.self),
            OFMethods.create: handlerFor(OFEmbeddedAccount.self),
            OFMethods.recover: handlerFor(OFEmbeddedAccount.self),
            OFMethods.exportPrivateKey: handlerFor(OFExportPrivateKeyResponse.self),
            OFMethods.list: handlerFor(OFListResponse.self),
            OFMethods.ping: handlerFor(OFPingResponse.self),
            OFMethods.signMessage: handlerFor(OFSignMessageResponse.self),
            OFMethods.getEmbeddedState: handlerFor(OFGetEmbeddedStateResponse.self),
            OFMethods.getURL: handlerFor(OFGetURLResponse.self),
            OFMethods.sendSignatureTransactionIntentRequest: handlerFor(OFSendSignatureTransactionIntentRequestResponse.self),
            OFMethods.sendSignatureSessionRequest: handlerFor(OFSessionResponse.self),
            OFMethods.getUserInstance: handlerFor(OFUser.self),
            OFMethods.getAccessToken: handlerFor(OFGetAccessTokenResponse.self),
            OFScriptMessageProcessor.embeddedStateChanged: handlerFor(Int.self),
        ]
    }

    private func handlerFor<T: Decodable>(_ type: T.Type) -> (Any?, String) -> Void {
        return { [weak self] data, method in
            self?.decodeAndHandle(type, from: data, method: method)
        }
    }

    // Helper to decode and handle the model
    private func decodeAndHandle<T: Decodable>(_ type: T.Type, from data: Any?, method: String) {
        let notificationName = Notification.Name(method)
        var object: Any? = nil
        var userInfo = ["success": true]

        func postNotification() {
            NotificationCenter.default.post(
                name: notificationName,
                object: object,
                userInfo: userInfo)
        }

        do {
            var jsonData: Data?

            // Treat empty data (nil, empty dict, empty string) as allowed: post nil object
            if data == nil ||
                (data as? [String: Any])?.isEmpty == true ||
                (data as? String)?.isEmpty == true {
                postNotification()
                print("No data to decode for \(method) (empty is allowed)")
                return
            }
            if let dict = data as? [String: Any] {
                if T.self == String.self {
                    let dataJson = try JSONSerialization.data(withJSONObject: dict, options: [])
                    if let jsonString = String(data: dataJson, encoding: .utf8) {
                        object = jsonString
                        postNotification()
                        return
                    }
                }
                jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
            } else if let d = data as? T {
                object = d
                postNotification()
                return
            } else {
                print("Data is not valid JSON for \(method)")
                userInfo = ["success": false]
                postNotification()
                return
            }
            guard let jsonData else {
                print("decodeAndHandle: missing jsonData for \(method)")
                userInfo = ["success": false]
                postNotification()
                return
            }
            object = try jsonDecoder.decode(T.self, from: jsonData)
            postNotification()
            print("Decoded \(method) data:", String(describing: object))
        } catch {
            print("Decoding error for \(method):", error)
            userInfo = ["success": false]
            postNotification()
        }
    }

    private func handleError(_ dict: [String: Any], method: String) {
        let errorMsg = dict["error"] as? String ?? "Unknown error"
        NotificationCenter.default.post(
            name: Notification.Name(method),
            object: nil,
            userInfo: ["success": false, "errorMessage": errorMsg]
        )
        print("\(method) error: \(errorMsg)")
    }
}
