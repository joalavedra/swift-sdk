//
//  OpenfortEIP1193Provider.swift
//  OpenfortAuthorization
//
//  Created by Pavlo Hurkovskyi on 2025-08-13.
//

import Foundation
import WebKit
@preconcurrency import Web3

/// Bridges Openfort’s JS EIP-1193 provider to Boilertalk/Web3.swift's `Web3Provider`.
/// It forwards JSON-RPC calls through the WKWebView using `provider.request({ method, params })`.
public final class OpenfortEIP1193Web3Provider: @preconcurrency Web3Provider {

    // MARK: - Web3Provider conformance hooks (not used by this protocol directly, but Web3 may inspect them elsewhere)
    public typealias Web3ResponseCompletion<Result: Codable> = @Sendable (_ resp: Web3Response<Result>) -> Void

    // MARK: - Internals
    private weak var webView: WKWebView?
    private let callbackQueue: DispatchQueue
    private let getProviderParams: OFGetEthereumProviderParams?
    
    /// - Parameters:
    ///   - webView: The `WKWebView` hosting the Openfort page where `openfort.getEthereumProvider()` is available.
    ///   - getProviderParams: Optional parameters forwarded to `openfort.getEthereumProvider(...)` (e.g., policy, chains, providerInfo, announceProvider). If `nil`, the provider is requested without arguments.
    ///   - callbackQueue: The dispatch queue on which `Web3Response` callbacks are delivered. Defaults to `.main`.
    public init(webView: WKWebView,
                getProviderParams: OFGetEthereumProviderParams? = nil,
                callbackQueue: DispatchQueue = .main) {
        self.webView = webView
        self.getProviderParams = getProviderParams
        self.callbackQueue = callbackQueue
    }

    // MARK: - Web3Provider requirement

    @MainActor public func send<Params, Result: Sendable>(
        request: RPCRequest<Params>,
        response: @escaping Web3ResponseCompletion<Result>
    ) {
        guard let webView else {
            callbackQueue.async { response(Web3Response<Result>(error: Web3Response<Result>.Error.connectionFailed(nil))) }
            return
        }

        // 1) Build JSON for `params`
        let paramsJSONString = makeParamsJSONString(request.params) ?? "[]"

        // 2) Build the async function body. We must use `callAsyncJavaScript`, which awaits the
        //    returned promise — `evaluateJavaScript` does not, and a returned Promise fails to
        //    bridge ("WKError code 5: result of an unsupported type"), breaking every request.
        let body = """
        if (!window.__ofProvider) {
          if (!window.openfort || !window.openfort.embeddedWalletInstance) {
            throw new Error('Openfort embedded wallet not available in page');
          }
          window.__ofProvider = await window.openfort.embeddedWalletInstance.getEthereumProvider(\(getProviderParamsJSArgument()));
        }
        return await window.__ofProvider.request({
          method: "\(request.method)",
          params: \(paramsJSONString)
        });
        """

        // 3) Evaluate and map back to Web3Response<Result>
        webView.callAsyncJavaScript(body, arguments: [:], in: nil, in: .page, completionHandler: { jsResult in
            switch jsResult {
            case .failure(let jsError):
                let wrapped = NSError(
                    domain: "OpenfortEIP1193Web3Provider", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: Self.jsErrorMessage(jsError)]
                )
                self.callbackQueue.async {
                    response(Web3Response<Result>(error: Web3Response<Result>.Error.requestFailed(wrapped)))
                }
            case .success(let value):
                if let decoded: Result = self.decodeResult(value) {
                    self.callbackQueue.async {
                        response(Web3Response<Result>(status: .success(decoded)))
                    }
                } else {
                    self.callbackQueue.async {
                        response(Web3Response<Result>(error: Web3Response<Result>.Error.decodingError(nil)))
                    }
                }
            }
        })
    }
    
    // MARK: - Async request (Web3.swift-free)

    /// EIP-1193 `request`, async and free of Web3.swift types. Forwards `{ method, params }` to the
    /// page provider and returns the result as a `String` (e.g. a transaction hash for
    /// `eth_sendTransaction`, or a hex value for `eth_call` / `eth_chainId`). Object/array results
    /// are returned as a JSON string. Throws `OFProviderError` on bridge or provider errors.
    ///
    /// Use this instead of `send(request:response:)` when you don't want to depend on Boilertalk
    /// Web3.swift (`RPCRequest` / `Web3Response`) just to make a JSON-RPC call.
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

    /// Extracts the underlying JavaScript exception message from a `callAsyncJavaScript` error,
    /// which otherwise surfaces only as a generic "A JavaScript exception occurred".
    static func jsErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        if let message = nsError.userInfo["WKJavaScriptExceptionMessage"] as? String, !message.isEmpty {
            return message
        }
        return nsError.localizedDescription
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
        guard let p = getProviderParams else { return "undefined" }
        do {
            let data = try JSONEncoder().encode(p)
            return String(data: data, encoding: .utf8) ?? "undefined"
        } catch {
            return "undefined"
        }
    }


    // MARK: - Encoding helpers

    /// Turns generic `Params?` into a JSON string literal suitable to embed into JS.
    private func makeParamsJSONString<Params>(_ params: Params?) -> String? {
        guard let params else { return "[]" }

        // First, try direct JSON encoding (works for Encodable arrays/dicts/primitives).
        if let encodable = params as? Encodable {
            do {
                let data = try encodeEncodableToJSON(encodable)
                return String(data: data, encoding: .utf8)
            } catch {
                // fallthrough
            }
        }

        // Next, try to convert common Foundation shapes
        if JSONSerialization.isValidJSONObject(params) {
            if let data = try? JSONSerialization.data(withJSONObject: params, options: []) {
                return String(data: data, encoding: .utf8)
            }
        }

        // As a last resort: wrap single items into an array
        if let data = try? JSONSerialization.data(withJSONObject: [params], options: []) {
            return String(data: data, encoding: .utf8)
        }

        return nil
    }

    private func encodeEncodableToJSON(_ value: Encodable) throws -> Data {
        struct AnyEncodable: Encodable {
            let wrapped: Encodable
            func encode(to encoder: Encoder) throws { try wrapped.encode(to: encoder) }
        }
        return try JSONEncoder().encode(AnyEncodable(wrapped: value))
    }

    // MARK: - Decoding helpers

    /// Attempts to coerce the JS `result` into `Result`.
    private func decodeResult<Result: Codable>(_ any: Any?) -> Result? {
        guard let any else { return nil }

        // Fast-path for common primitives
        if Result.self == String.self, let s = any as? String { return s as? Result }
        if Result.self == Bool.self,   let b = any as? Bool   { return b as? Result }
        if Result.self == Int.self,    let i = any as? Int    { return i as? Result }
        if Result.self == Double.self, let d = any as? Double { return d as? Result }

        // If the result is already the right type (rare), just cast
        if let casted = any as? Result {
            return casted
        }

        // Otherwise, try JSON round‑trip:
        // - If it's JSON-serializable (dict/array/primitive), serialize then decode
        if JSONSerialization.isValidJSONObject(any),
           let data = try? JSONSerialization.data(withJSONObject: any, options: []) {
            if let decoded = try? JSONDecoder().decode(Result.self, from: data) {
                return decoded
            }
        }

        // If it’s a primitive (e.g., string) but Result is Codable (e.g., String),
        // encode that primitive alone to JSON data and decode it into Result.
        if let s = any as? String, let data = try? JSONEncoder().encode(s),
           let decoded = try? JSONDecoder().decode(Result.self, from: data) {
            return decoded
        }
        if let b = any as? Bool, let data = try? JSONEncoder().encode(b),
           let decoded = try? JSONDecoder().decode(Result.self, from: data) {
            return decoded
        }
        if let n = any as? NSNumber,
           let data = try? JSONEncoder().encode(n.stringValue),
           let decoded = try? JSONDecoder().decode(Result.self, from: data) {
            return decoded
        }

        return nil
    }
}

public enum OFProviderError: Error, LocalizedError {
    case connectionFailed
    case emptyResponse
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed: return "The Openfort provider WebView is unavailable."
        case .emptyResponse:    return "The Openfort provider returned no response."
        case .requestFailed(let message): return message
        }
    }
}
