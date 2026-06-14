import Foundation
import WebKit

public extension OFSDK {
    /// Sends a **gasless EIP-7702 transaction** from the embedded wallet's EOA, sponsored by
    /// `policy`. A bundled viem flow inside the SDK WebView signs the one-time 7702 authorization
    /// and the user operation through the embedded signer — the EOA private key never leaves
    /// Openfort's secure signer — and submits the user operation via Openfort's bundler + paymaster.
    /// Returns the transaction hash.
    ///
    /// Configure the wallet as `.eoa` for this flow — the delegation is layered on at send time.
    ///
    /// - Parameters:
    ///   - to: Destination address of the call.
    ///   - data: Calldata (default `"0x"`).
    ///   - value: Wei value as a hex or decimal string (default `"0x0"`).
    ///   - policy: Sponsorship policy id passed to the paymaster.
    ///   - chainId: Target chain (default Base Sepolia, `84532`). Base mainnet (`8453`) is also
    ///     known; any other id is built dynamically and requires `rpcUrl`.
    ///   - implementationAddress: Optional override for the Simple7702Account implementation the
    ///     authorization delegates to. Defaults to viem's bundled implementation.
    ///   - rpcUrl: Optional public RPC override for the chain (required for unknown chain ids).
    @MainActor
    @discardableResult
    func sendDelegatedTransaction(
        to: String,
        data: String = "0x",
        value: String = "0x0",
        policy: String,
        chainId: Int = 84532,
        implementationAddress: String? = nil,
        rpcUrl: String? = nil
    ) async throws -> String {
        guard let webView else { throw OFError.notReady("SDK WebView is unavailable.") }
        guard let config = OFConfig.loadFromMainBundle() else {
            throw OFError.missingConfiguration("OFConfig.plist is missing or invalid.")
        }

        var args: [String: Any] = [
            "to": to,
            "data": data,
            "value": value,
            "policyId": policy,
            "publishableKey": config.openfortPublishableKey,
            "chainId": chainId,
        ]
        if let implementationAddress { args["implementationAddress"] = implementationAddress }
        if let rpcUrl { args["rpcUrl"] = rpcUrl }
        guard let argsData = try? JSONSerialization.data(withJSONObject: args),
              let argsJSON = String(data: argsData, encoding: .utf8) else {
            throw OFError.encodingFailed
        }
        return try await OF7702Runner.run(argsJSON: argsJSON, on: webView)
    }
}

/// Kicks off `window.__ofSend7702(...)` in the page's default world and polls for the settled
/// result — the same pattern the EIP-1193 provider uses, since `evaluateJavaScript` can't await a
/// promise but can read a value once it resolves.
enum OF7702Runner {
    @MainActor private static var counter = 0

    @MainActor
    static func run(argsJSON: String, on webView: WKWebView) async throws -> String {
        counter += 1
        let id = counter
        let kickoff = """
        (function(){
          window.__of7702 = window.__of7702 || {};
          window.__of7702[\(id)] = null;
          (async function(){
            try {
              if (!window.__ofSend7702) throw new Error('EIP-7702 helper not loaded');
              const result = await window.__ofSend7702(\(argsJSON));
              window.__of7702[\(id)] = { ok: true, result: String(result) };
            } catch (e) {
              window.__of7702[\(id)] = { ok: false, error: (e && (e.message || String(e))) || 'EIP-7702 send failed' };
            }
          })();
        })();
        """
        _ = try await evaluate(kickoff, on: webView)

        let poll = "JSON.stringify((window.__of7702 && window.__of7702[\(id)]) || null)"
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if let json = try await evaluate(poll, on: webView), json != "null", !json.isEmpty,
               let data = json.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                _ = try? await evaluate("delete window.__of7702[\(id)]", on: webView)
                if (object["ok"] as? Bool) == true, let hash = object["result"] as? String {
                    return hash
                }
                throw OFProviderError.requestFailed((object["error"] as? String) ?? "EIP-7702 send failed")
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw OFProviderError.requestFailed("EIP-7702 transaction timed out")
    }

    @MainActor
    private static func evaluate(_ js: String, on webView: WKWebView) async throws -> String? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String?, Error>) in
            webView.evaluateJavaScript(js) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value as? String)
                }
            }
        }
    }
}
