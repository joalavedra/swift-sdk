//
//  OpenfortEIP1193Provider.swift
//  OpenfortAuthorization
//
//  Created by Pavlo Hurkovskyi on 2025-08-13.
//

import Foundation
import WebKit

/// Bridges Openfort's in-page EIP-1193 provider to Swift. Forwards JSON-RPC calls through the
/// `WKWebView` to `window.openfort.embeddedWalletInstance.getEthereumProvider().request(...)` and
/// returns the result — with no third-party Web3 dependency.
public final class OpenfortEIP1193Web3Provider {

    private weak var webView: WKWebView?
    private let getProviderParams: OFGetEthereumProviderParams?

    /// - Parameters:
    ///   - webView: The `WKWebView` hosting the Openfort page where `getEthereumProvider()` is available.
    ///   - getProviderParams: Optional parameters forwarded to `getEthereumProvider(...)` (e.g. policy,
    ///     chains, providerInfo, announceProvider). If `nil`, the provider is requested without arguments.
    public init(webView: WKWebView, getProviderParams: OFGetEthereumProviderParams? = nil) {
        self.webView = webView
        self.getProviderParams = getProviderParams
    }

    // MARK: - Request

    /// EIP-1193 `request`. Forwards `{ method, params }` to the page provider and returns the result
    /// as a `String` (e.g. a transaction hash for `eth_sendTransaction`, or a hex value for
    /// `eth_call` / `eth_chainId`). Object/array results are returned as a JSON string. Throws
    /// `OFProviderError` on bridge or provider errors.
    @MainActor
    @discardableResult
    public func request(method: String, params: [Any] = []) async throws -> String? {
        guard let webView else { throw OFProviderError.connectionFailed }

        let paramsJSON = (try? JSONSerialization.data(withJSONObject: params))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        // `window.openfort` is injected by the SDK's legacy user scripts and lives in the page's
        // default world — `callAsyncJavaScript`'s named content worlds (`.page`/`.defaultClient`)
        // can't see it. So we run in that world via `evaluateJavaScript` (the same path the SDK's
        // other bridges use), kick off the async request, stash the settled result on `window`,
        // and poll for it — `evaluateJavaScript` can't await a promise, but it can read a value.
        let id = Self.nextRequestId()
        let kickoff = """
        (function(){
          window.__ofRpc = window.__ofRpc || {};
          window.__ofRpc[\(id)] = null;
          (async function(){
            try {
              if (!window.__ofProvider) {
                if (!window.openfort || !window.openfort.embeddedWalletInstance) {
                  throw new Error('Openfort embedded wallet not available in page');
                }
                window.__ofProvider = await window.openfort.embeddedWalletInstance.getEthereumProvider(\(getProviderParamsJSArgument()));
              }
              const result = await window.__ofProvider.request({ method: "\(method)", params: \(paramsJSON) });
              window.__ofRpc[\(id)] = { ok: true, result: (result === undefined ? null : result) };
            } catch (e) {
              window.__ofRpc[\(id)] = { ok: false, error: (e && (e.message || String(e))) || 'Provider request failed' };
            }
          })();
        })();
        """
        _ = try await Self.evaluate(kickoff, on: webView)

        let poll = "JSON.stringify((window.__ofRpc && window.__ofRpc[\(id)]) || null)"
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if let json = try await Self.evaluate(poll, on: webView), json != "null", !json.isEmpty,
               let data = json.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                _ = try? await Self.evaluate("delete window.__ofRpc[\(id)]", on: webView)
                if (object["ok"] as? Bool) == true {
                    return Self.stringify(object["result"])
                }
                throw OFProviderError.requestFailed((object["error"] as? String) ?? "Provider request failed")
            }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        throw OFProviderError.requestFailed("Provider request timed out")
    }

    @MainActor private static var requestCounter = 0
    @MainActor private static func nextRequestId() -> Int {
        requestCounter += 1
        return requestCounter
    }

    /// Runs JS in the page's default world (via `evaluateJavaScript`) and returns a String result.
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

    /// Coerces a JS result value into a `String` (passing strings through, JSON-encoding objects).
    private static func stringify(_ any: Any?) -> String? {
        guard let any, !(any is NSNull) else { return nil }
        if let string = any as? String { return string }
        if let number = any as? NSNumber { return number.stringValue }
        if JSONSerialization.isValidJSONObject(any),
           let data = try? JSONSerialization.data(withJSONObject: any),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return String(describing: any)
    }

    private func getProviderParamsJSArgument() -> String {
        guard let params = getProviderParams else { return "undefined" }
        do {
            let data = try JSONEncoder().encode(params)
            return String(data: data, encoding: .utf8) ?? "undefined"
        } catch {
            return "undefined"
        }
    }
}

/// Errors raised by the Openfort EIP-1193 provider bridge.
public enum OFProviderError: Error, LocalizedError {
    case connectionFailed
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed: return "The Openfort provider WebView is unavailable."
        case .requestFailed(let message): return message
        }
    }
}
