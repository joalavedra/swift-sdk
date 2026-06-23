//
//  OFFunding.swift
//  OpenfortSwift
//
//  SwiftUI-facing funding (cross-chain deposit) controller — the Swift counterpart
//  of `@openfort/react`'s `useFunding` hook. Hold one per deposit flow with
//  `@StateObject` and drive it with `fund` / `createSession` / `track` / `payLink`,
//  observing `session` / `status` / `loading` / `error` for UI.
//

import Combine
import Foundation

/// Errors surfaced by ``OFFunding``.
public enum OFFundingError: LocalizedError {
    /// The funding bridge completed without returning the expected payload.
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "The Openfort funding bridge returned an empty response."
        }
    }
}

/// Observable controller over the funding session flow.
///
/// A session is one deposit attempt against a destination: ``fund(_:_:)`` creates a
/// session, sets a payment method, and polls until terminal, publishing each update.
/// The resolved `session.paymentMethod` carries everything a custom UI (or an agent)
/// needs — a receiver address, a scannable URI, prefilled wallet deeplinks, and CEX
/// guidance.
///
/// ```swift
/// struct DepositView: View {
///     @StateObject private var funding = OFFunding()
///     var body: some View {
///         // ... pick a source, then:
///         // try await funding.fund(target, .evm(source: source))
///         // render funding.session?.paymentMethod?.receiverAddress / addressUri (QR)
///     }
/// }
/// ```
@MainActor
public final class OFFunding: ObservableObject {

    /// The current session, or `nil` before the first call / after ``reset()``.
    @Published public private(set) var session: OFFundingSession?
    /// `true` while a session is being created and its deposit address fetched.
    @Published public private(set) var loading: Bool = false
    /// The last error thrown by a call, cleared at the start of the next one.
    @Published public private(set) var error: Error?
    /// `true` once the SDK bridge is ready (the funding namespace is then available).
    @Published public private(set) var isAvailable: Bool

    /// The current session status, or `nil` for the idle state (no session yet).
    public var status: OFFundingSessionStatus? { session?.status }

    private let sdk: OFSDK
    private let pollNanos: UInt64
    // Generation guard: only the latest fund()/track()/reset() updates state, so a
    // stale poll loop can't clobber newer state after reset.
    private var generation = 0

    /// - Parameters:
    ///   - sdk: The Openfort SDK instance. Defaults to ``OFSDK/shared``.
    ///   - pollInterval: Seconds between session polls while waiting for a terminal status.
    public init(sdk: OFSDK = .shared, pollInterval: TimeInterval = 4) {
        self.sdk = sdk
        self.pollNanos = UInt64(pollInterval * 1_000_000_000)
        self.isAvailable = sdk.isInitialized
        if !sdk.isInitialized {
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await self.sdk.waitUntilReady()
                self.isAvailable = self.sdk.isInitialized
            }
        }
    }

    /// Create a session, set a payment method, and poll until the session reaches a
    /// terminal status (`succeeded` / `bounced` / `expired`).
    ///
    /// - Parameters:
    ///   - target: Where the funded crypto should land.
    ///   - paymentMethod: The source route the user commits to (`evm` / `solana` / `cex`).
    /// - Returns: The terminal session.
    @discardableResult
    public func fund(
        _ target: OFFundingTarget,
        _ paymentMethod: OFFundingPaymentMethodInput
    ) async throws -> OFFundingSession {
        generation += 1
        let gen = generation
        error = nil
        loading = true
        do {
            guard let created = try await sdk.fundingCreateSession(target: target) else {
                throw OFFundingError.emptyResponse
            }
            guard let current = try await sdk.fundingSetPaymentMethod(
                sessionId: created.id,
                paymentMethod: paymentMethod,
                clientSecret: created.clientSecret
            ) else {
                throw OFFundingError.emptyResponse
            }
            guard gen == generation else { return current }
            session = current
            loading = false
            return try await pollUntilTerminal(current, generation: gen)
        } catch {
            if gen == generation {
                self.error = error
                loading = false
            }
            throw error
        }
    }

    /// Create a bare session for a target (no payment method, no polling) — used to
    /// mint a pay-link, where only the session id + secret are needed.
    @discardableResult
    public func createSession(_ target: OFFundingTarget) async throws -> OFFundingSession {
        guard let created = try await sdk.fundingCreateSession(target: target) else {
            throw OFFundingError.emptyResponse
        }
        return created
    }

    /// Poll an already-created session (id + clientSecret) until it reaches a terminal
    /// status, publishing `session` / `status` updates as it goes. Used by the CEX rail,
    /// which hands off to a hosted Coinbase flow and then watches the session settle.
    @discardableResult
    public func track(id: String, clientSecret: String) async throws -> OFFundingSession {
        generation += 1
        let gen = generation
        error = nil
        do {
            guard let start = try await sdk.fundingGetSession(sessionId: id, clientSecret: clientSecret) else {
                throw OFFundingError.emptyResponse
            }
            guard gen == generation else { return start }
            session = start
            return try await pollUntilTerminal(start, generation: gen)
        } catch {
            if gen == generation { self.error = error }
            throw error
        }
    }

    /// Resolve a hosted Coinbase pay URL for an existing session.
    public func payLink(_ params: OFPayLinkParams) async throws -> String {
        guard let url = try await sdk.fundingPayLink(params) else {
            throw OFFundingError.emptyResponse
        }
        return url
    }

    /// Reset to the idle state (e.g. when leaving the deposit flow). Stops any
    /// in-flight poll loop.
    public func reset() {
        generation += 1
        session = nil
        error = nil
        loading = false
    }

    /// Poll a session until terminal, publishing each update. `generation` guards a
    /// stale loop from clobbering newer state after a reset or a newer call.
    private func pollUntilTerminal(
        _ start: OFFundingSession,
        generation gen: Int
    ) async throws -> OFFundingSession {
        var current = start
        while !current.status.isTerminal {
            try await Task.sleep(nanoseconds: pollNanos)
            guard gen == generation else { return current }
            guard let next = try await sdk.fundingGetSession(
                sessionId: current.id, clientSecret: current.clientSecret
            ) else {
                return current
            }
            guard gen == generation else { return next }
            current = next
            session = next
        }
        return current
    }
}
