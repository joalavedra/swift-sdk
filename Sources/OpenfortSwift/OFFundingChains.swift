//
//  OFFundingChains.swift
//  OpenfortSwift
//
//  SwiftUI-facing source-chain catalog loader — the Swift counterpart of
//  `@openfort/react`'s `useFundingChains` hook. Hold one with `@StateObject`,
//  call `load`, and bind a source picker to `chains` / `loading` / `error`
//  instead of hardcoding the routable chains in the UI.
//

import Combine
import Foundation

/// Observable loader for the funding source-chain catalog.
///
/// The funding rail routes a deposit from a source chain + currency to a destination.
/// ``load()`` fetches the live, routable source chains so a picker can render them
/// instead of relying on a hardcoded list.
///
/// ```swift
/// struct SourcePicker: View {
///     @StateObject private var catalog = OFFundingChains()
///     var body: some View {
///         List(catalog.chains, id: \.id) { chain in Text(chain.name) }
///             .task { await catalog.load() }
///     }
/// }
/// ```
@MainActor
public final class OFFundingChains: ObservableObject {

    /// The routable source chains, or empty before the first ``load()`` / after a failure.
    @Published public private(set) var chains: [OFFundingChain] = []
    /// `true` while the source-chain catalog is being fetched.
    @Published public private(set) var loading: Bool = false
    /// The last error thrown by ``load()``, cleared at the start of the next one.
    @Published public private(set) var error: Error?

    private let sdk: OFSDK

    /// - Parameter sdk: The Openfort SDK instance. Defaults to ``OFSDK/shared``.
    public init(sdk: OFSDK = .shared) {
        self.sdk = sdk
    }

    /// Fetch the routable source chains, publishing `loading` / `chains` / `error`.
    ///
    /// On success `chains` holds the live catalog; on failure `error` is set and
    /// `chains` is left untouched. A `nil` bridge response yields an empty catalog.
    public func load() async {
        error = nil
        loading = true
        do {
            chains = try await sdk.fundingChains() ?? []
        } catch {
            self.error = error
        }
        loading = false
    }
}
