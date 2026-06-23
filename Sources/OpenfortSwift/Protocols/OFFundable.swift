//
//  OFFundable.swift
//  OpenfortSwift
//
//  Bridge surface for the openfort-js `funding` namespace (cross-chain deposit
//  sessions). These are the atomic primitives — create a session, set its single
//  payment method, read it, mint a Coinbase pay-link, and list source chains. The
//  poll-until-terminal loop lives in ``OFFunding`` (the SwiftUI hook), not here, so
//  intermediate status updates can surface and a flow can be reset mid-poll.
//
//  Funding authenticates with the project publishable key and needs no logged-in
//  user, so these work for guest and authenticated sessions alike.
//

import Foundation

/// `OFFundable` exposes the Openfort funding (cross-chain deposit) namespace,
/// supporting both async/await and completion-handler usage.
public protocol OFFundable: OFOpenfortRootable {}

// Bridge param payloads. Encoded to JSON and handed to the `funding*Sync` shims in
// `openfort-sync.js`; synthesized `Encodable` omits `nil` optionals (so a missing
// `clientSecret` falls back to the SDK-remembered secret on the JS side).
private struct OFFundingCreateParams: Encodable {
    let target: OFFundingTarget
}

private struct OFFundingSetPaymentMethodParams: Encodable {
    let sessionId: String
    let paymentMethod: OFFundingPaymentMethodInput
    let clientSecret: String?
}

private struct OFFundingGetParams: Encodable {
    let sessionId: String
    let clientSecret: String?
}

public extension OFFundable {

    /// Creates a funding session for a destination, without a payment method yet.
    ///
    /// - Parameter target: Where the funded crypto should land.
    /// - Returns: The created session (`requires_payment_method`), or `nil` if the bridge returns no data.
    /// - Throws: An error if encoding fails or the JavaScript bridge reports a failure.
    func fundingCreateSession(target: OFFundingTarget) async throws -> OFFundingSession? {
        guard let jsonString = encodeToJSONString(OFFundingCreateParams(target: target)) else {
            throw OFError.encodingFailed
        }
        return try await evaluateAndObserveAsync(
            js: "window.fundingCreateSessionSync(\(jsonString));",
            method: OFMethods.fundingCreateSession,
            errorDomain: OFErrorDomains.fundingCreateSession
        )
    }

    func fundingCreateSession(
        target: OFFundingTarget,
        completion: @escaping (Result<OFFundingSession?, Error>) -> Void
    ) {
        Task {
            do { completion(.success(try await fundingCreateSession(target: target))) }
            catch { completion(.failure(error)) }
        }
    }

    /// Sets the single payment method (a committed source route) on a session,
    /// minting its deposit address.
    ///
    /// - Parameters:
    ///   - sessionId: The session to set the method on.
    ///   - paymentMethod: The source route the user commits to (`evm` / `solana` / `cex`).
    ///   - clientSecret: The session's client secret. Optional for sessions created on this SDK instance.
    /// - Returns: The updated session (`waiting_payment` with a resolved `paymentMethod`), or `nil`.
    /// - Throws: An error if encoding fails or the JavaScript bridge reports a failure.
    func fundingSetPaymentMethod(
        sessionId: String,
        paymentMethod: OFFundingPaymentMethodInput,
        clientSecret: String? = nil
    ) async throws -> OFFundingSession? {
        let params = OFFundingSetPaymentMethodParams(
            sessionId: sessionId, paymentMethod: paymentMethod, clientSecret: clientSecret
        )
        guard let jsonString = encodeToJSONString(params) else { throw OFError.encodingFailed }
        return try await evaluateAndObserveAsync(
            js: "window.fundingSetPaymentMethodSync(\(jsonString));",
            method: OFMethods.fundingSetPaymentMethod,
            errorDomain: OFErrorDomains.fundingSetPaymentMethod
        )
    }

    func fundingSetPaymentMethod(
        sessionId: String,
        paymentMethod: OFFundingPaymentMethodInput,
        clientSecret: String? = nil,
        completion: @escaping (Result<OFFundingSession?, Error>) -> Void
    ) {
        Task {
            do {
                let result = try await fundingSetPaymentMethod(
                    sessionId: sessionId, paymentMethod: paymentMethod, clientSecret: clientSecret
                )
                completion(.success(result))
            } catch { completion(.failure(error)) }
        }
    }

    /// Reads the current state of a funding session.
    ///
    /// - Parameters:
    ///   - sessionId: The session to read.
    ///   - clientSecret: The session's client secret. Optional for sessions created on this SDK instance.
    /// - Returns: The session, or `nil` if the bridge returns no data.
    /// - Throws: An error if encoding fails or the JavaScript bridge reports a failure.
    func fundingGetSession(sessionId: String, clientSecret: String? = nil) async throws -> OFFundingSession? {
        let params = OFFundingGetParams(sessionId: sessionId, clientSecret: clientSecret)
        guard let jsonString = encodeToJSONString(params) else { throw OFError.encodingFailed }
        return try await evaluateAndObserveAsync(
            js: "window.fundingGetSessionSync(\(jsonString));",
            method: OFMethods.fundingGetSession,
            errorDomain: OFErrorDomains.fundingGetSession
        )
    }

    func fundingGetSession(
        sessionId: String,
        clientSecret: String? = nil,
        completion: @escaping (Result<OFFundingSession?, Error>) -> Void
    ) {
        Task {
            do { completion(.success(try await fundingGetSession(sessionId: sessionId, clientSecret: clientSecret))) }
            catch { completion(.failure(error)) }
        }
    }

    /// Resolves a hosted Coinbase pay URL that delivers to the session's wallet.
    ///
    /// - Parameter params: Session id, amount, and (optionally) client secret + asset.
    /// - Returns: The pay URL, or `nil` if the bridge returns no data.
    /// - Throws: An error if encoding fails or the JavaScript bridge reports a failure.
    func fundingPayLink(_ params: OFPayLinkParams) async throws -> String? {
        guard let jsonString = encodeToJSONString(params) else { throw OFError.encodingFailed }
        return try await evaluateAndObserveAsync(
            js: "window.fundingPayLinkSync(\(jsonString));",
            method: OFMethods.fundingPayLink,
            errorDomain: OFErrorDomains.fundingPayLink
        )
    }

    func fundingPayLink(_ params: OFPayLinkParams, completion: @escaping (Result<String?, Error>) -> Void) {
        Task {
            do { completion(.success(try await fundingPayLink(params))) }
            catch { completion(.failure(error)) }
        }
    }

    /// Lists the source chains + currencies the rail can route from, for a source picker.
    ///
    /// - Returns: The routable source chains, or `nil` if the bridge returns no data.
    /// - Throws: An error if the JavaScript bridge reports a failure.
    func fundingChains() async throws -> [OFFundingChain]? {
        try await evaluateAndObserveAsync(
            js: "window.fundingChainsSync();",
            method: OFMethods.fundingChains,
            errorDomain: OFErrorDomains.fundingChains
        )
    }

    func fundingChains(completion: @escaping (Result<[OFFundingChain]?, Error>) -> Void) {
        Task {
            do { completion(.success(try await fundingChains())) }
            catch { completion(.failure(error)) }
        }
    }
}
