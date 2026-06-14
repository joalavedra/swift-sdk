//
//  OFSDK.swift
//  OpenfortSwift
//
//  Created by Pavel Gurkovskii on 2025-07-03.
//

import WebKit
import Combine
import Security

@MainActor
public final class OFSDK: NSObject, OFOpenfortRootable, OFAuthorizable, OFProxible, OFEmbeddedWalletAccessable, OFUserAccessable {
    
    public static let shared = OFSDK()
    
    public internal(set) var webView: WKWebView?
    public internal(set) var jsonEncoder: JSONEncoder = JSONEncoder()
    public internal(set) var isInitialized: Bool = false
    
    @Published public private(set) var embeddedState: OFEmbeddedState?
    public var embeddedStatePublisher: Published<OFEmbeddedState?>.Publisher { $embeddedState }
    
    private static var initialized: Bool = false
    private var coordinator = OFWebViewCoordinator()
    private var messageHandler = OFScriptMessageHandler()
    private var embeddedStateTimer: Timer?
    private var getAccessToken: (() async throws -> String?)?
    private var lastInitError: String?

    @MainActor
    public static func setupSDK(thirdParty: OFAuthProvider? = nil, getAccessToken: (() async throws -> String?)? = nil) throws {
        if initialized && thirdParty == nil {
            return
        }

        // Fail fast with actionable errors, rather than letting these surface later as an
        // opaque INVALID_CONFIGURATION from the JS bridge.
        let keychainStatus = OFKeychainHelper.accessibilityStatus()
        guard keychainStatus == errSecSuccess else {
            throw OFError.keychainInaccessible(status: keychainStatus)
        }
        guard OFConfig.loadFromMainBundle() != nil else {
            throw OFError.missingConfiguration(
                "OFConfig.plist is missing or invalid. Add it to your app target with at least "
                + "`openfortPublishableKey` and `shieldPublishableKey`."
            )
        }

        shared.setupInstance(thirdParty: thirdParty, getAccessToken: getAccessToken)
        initialized = true
    }

    /// Suspends until the SDK's WebView bridge has finished loading and is ready to accept calls.
    /// `setupSDK()` returns *before* the bridge is ready, so prefer awaiting this (or observing
    /// `.openfortReady`) before your first SDK call. Throws `OFError.notReady` on failure/timeout.
    public func waitUntilReady(timeout: TimeInterval = 15) async throws {
        if isInitialized { return }
        let start = Date()
        while !isInitialized {
            if let error = lastInitError { throw OFError.notReady(error) }
            if Date().timeIntervalSince(start) > timeout {
                throw OFError.notReady("WebView bridge did not load within \(Int(timeout))s.")
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    
    @MainActor
    private func setupInstance(thirdParty: OFAuthProvider? = nil, getAccessToken: (() async throws -> String?)? = nil) {
        coordinator.didLoad = { [weak self] in
            self?.isInitialized = true
            self?.lastInitError = nil
            if self?.embeddedStateTimer == nil {
                self?.startPollingEmbeddedState()
            }
            NotificationCenter.default.post(name: .openfortReady, object: self)
        }

        coordinator.didFailedToLoad = { [weak self] error in
            self?.isInitialized = false
            self?.lastInitError = (error as NSError).localizedDescription
            self?.stopPollingEmbeddedState()
            NotificationCenter.default.post(name: .openfortInitError, object: self, userInfo: ["error": (error as NSError).localizedDescription])
        }
        
        self.webView = OFWebView(fileUrl: contentUrl, delegate: coordinator, scriptMessageHandler: messageHandler, provider: thirdParty?.rawValue, getAccessToken: getAccessToken)
    }
    
    private func startPollingEmbeddedState() {
        embeddedStateTimer?.invalidate()
        embeddedStateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.getEmbeddedState(completion: { result in
                    switch result {
                    case .success(let newValue):
                        self.embeddedState = OFEmbeddedState(rawValue: newValue ?? 0)
                    case .failure(_):
                        break
                    }
                })
            }
        }
    }
    
    private func stopPollingEmbeddedState() {
        embeddedStateTimer?.invalidate()
        embeddedStateTimer = nil
    }
    
    private var contentUrl: URL {
        Bundle.module.url(forResource: "index", withExtension: "html")!
    }
}

public extension Notification.Name {
    /// Posted (object: `OFSDK.shared`) when the embedded SDK WebView bridge has finished loading
    /// and is ready to accept calls.
    static let openfortReady = Notification.Name("openfortReady")
    /// Posted when the SDK WebView bridge fails to load. `userInfo["error"]` holds a description.
    static let openfortInitError = Notification.Name("openfortInitError")
}
