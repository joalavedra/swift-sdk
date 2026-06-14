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
    private var getAccessToken: (() async throws -> String?)?
    private var lastInitError: String?

    // Embedded-state tracking. openfort-js has no "embedded state changed" event
    // (getEmbeddedState() is a value derived from storage), but it does emit lifecycle
    // events — onAuthSuccess/onLogout/onEmbeddedWalletCreated/etc. — on every transition
    // that moves that value. The `__ofWatchEmbeddedState` JS hook subscribes to those and
    // pushes the new state here, replacing the old always-on 1s busy poll.
    private var embeddedStateObserver: NSObjectProtocol?
    // configure() persists the signer (NOT_CONFIGURED -> READY) without emitting an event, so
    // a short bounded poll backstops it: a handful of fast ticks that stop once the state
    // settles, re-armed after each event. This is not the old forever-running 1s loop.
    private var embeddedStateBackstopTimer: Timer?
    private var embeddedStateBackstopTicks = 0
    private static let backstopInterval: TimeInterval = 0.25
    private static let backstopMaxTicks = 12

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
            self?.startTrackingEmbeddedState()
            NotificationCenter.default.post(name: .openfortReady, object: self)
        }

        coordinator.didFailedToLoad = { [weak self] error in
            self?.isInitialized = false
            self?.lastInitError = (error as NSError).localizedDescription
            self?.stopTrackingEmbeddedState()
            NotificationCenter.default.post(name: .openfortInitError, object: self, userInfo: ["error": (error as NSError).localizedDescription])
        }

        self.webView = OFWebView(fileUrl: contentUrl, delegate: coordinator, scriptMessageHandler: messageHandler, provider: thirdParty?.rawValue, getAccessToken: getAccessToken)
    }

    /// Wires up event-driven embedded-state tracking once the bridge is ready: observe the
    /// `embeddedStateChanged` pushes from the JS lifecycle hook, install that hook, and run a
    /// one-shot bounded backstop poll for the eventless configure() -> READY transition.
    private func startTrackingEmbeddedState() {
        guard embeddedStateObserver == nil else { return }

        embeddedStateObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name(OFScriptMessageProcessor.embeddedStateChanged),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let rawValue = notification.object as? Int else { return }
            Task { @MainActor [weak self] in
                self?.applyEmbeddedState(rawValue)
            }
        }

        webView?.evaluateJavaScript("window.__ofWatchEmbeddedState && window.__ofWatchEmbeddedState();")
        startBackstopPoll()
    }

    private func stopTrackingEmbeddedState() {
        if let observer = embeddedStateObserver {
            NotificationCenter.default.removeObserver(observer)
            embeddedStateObserver = nil
        }
        embeddedStateBackstopTimer?.invalidate()
        embeddedStateBackstopTimer = nil
        embeddedStateBackstopTicks = 0
    }

    private func applyEmbeddedState(_ rawValue: Int) {
        let newState = OFEmbeddedState(rawValue: rawValue)
        if newState != embeddedState {
            embeddedState = newState
            // A change may be the start of a multi-step transition the JS events don't fully
            // cover (e.g. NOT_CONFIGURED -> configure() -> READY emits nothing). Re-arm the
            // bounded backstop so we converge on the settled value without a forever loop.
            startBackstopPoll()
        }
    }

    /// Polls a few times in quick succession, then stops. Covers the window before the JS
    /// hook is wired and the eventless configure() -> READY transition. Self-terminating —
    /// this is deliberately not the old always-on 1s loop.
    private func startBackstopPoll() {
        embeddedStateBackstopTimer?.invalidate()
        embeddedStateBackstopTicks = 0
        embeddedStateBackstopTimer = Timer.scheduledTimer(
            withTimeInterval: Self.backstopInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.runBackstopTick()
            }
        }
    }

    /// One backstop poll iteration on the main actor. Stops the timer via the stored
    /// reference (not the closure's `timer` arg) to keep the work main-actor isolated.
    private func runBackstopTick() {
        embeddedStateBackstopTicks += 1
        if embeddedStateBackstopTicks >= Self.backstopMaxTicks {
            embeddedStateBackstopTimer?.invalidate()
            embeddedStateBackstopTimer = nil
        }
        getEmbeddedState { [weak self] result in
            if case .success(let newValue) = result {
                self?.applyEmbeddedStateFromBackstop(newValue ?? 0)
            }
        }
    }

    /// Backstop-only state apply: updates the published value without re-arming the poll
    /// (the poll re-arm lives in `applyEmbeddedState`, reserved for the event path) to avoid
    /// a tick perpetually restarting itself.
    private func applyEmbeddedStateFromBackstop(_ rawValue: Int) {
        let newState = OFEmbeddedState(rawValue: rawValue)
        if newState != embeddedState {
            embeddedState = newState
        }
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
