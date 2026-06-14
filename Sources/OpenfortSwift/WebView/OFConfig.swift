import Foundation

internal struct OFConfig: Codable {
    let backendUrl: String?
    let iframeUrl: String?
    let openfortPublishableKey: String
    let shieldPublishableKey: String
    let shieldUrl: String?
    // Optional: a missing `debug` key must not make the whole plist fail to decode.
    let debug: Bool?
    
    static func loadFromMainBundle() -> OFConfig? {
        guard let url = Bundle.main.url(forResource: "OFConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url) else {
            print("OFConfig.plist not found")
            return nil
        }
        
        do {
            let decoder = PropertyListDecoder()
            return try decoder.decode(OFConfig.self, from: data)
        } catch {
            print("Failed to decode OFConfig.plist:", error)
            return nil
        }
    }

    static func openfortSyncScript(provider: String? = nil) -> String {
        guard let config = loadFromMainBundle() else {
            print("OFConfig not loaded")
            return ""
        }

        let debugValue = config.debug ?? false

        var overrides: [String] = []
        if let iframeURL = config.iframeUrl, !iframeURL.isEmpty {
            overrides.append("                iframeUrl: '\(iframeURL)',")
        }
        if let shieldURL = config.shieldUrl, !shieldURL.isEmpty {
            overrides.append("                shieldUrl: '\(shieldURL)',")
        }
        if let backendURL = config.backendUrl, !backendURL.isEmpty {
            overrides.append("                backendUrl: '\(backendURL)',")
        }
        overrides.append("                storage: storage,")

        var thirdPartyAuthBlock = ""
        if let providerStr = provider {
            thirdPartyAuthBlock = """
                thirdPartyAuth: {
                    provider: '\(providerStr)',
                    getAccessToken: async () => {
                      try {
                        console.log('----- Requesting access token from native auth -----');
                        return await window.__ofAuthBridgeRequest('app:third-party-auth:getAccessToken');
                      } catch (e) {
                        console.error('getAccessToken bridge error', e);
                        return null;
                      }
                    },
                },
            """
        }

        let overridesString = overrides.joined(separator: "\n")

        // Get native app identifier (bundle identifier)
        let nativeAppIdentifier = Bundle.main.bundleIdentifier ?? "unknown"

        // JS helper for bridge
        let authBridgeHelper = """
            (function () {
              window.__ofAuthBridgeRequest = (eventName) => {
                const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.authHandler;
                if (!handler || typeof handler.postMessage !== 'function') {
                  console.error('[OF] authHandler not available');
                  return Promise.resolve(null);
                }
                try {
                  // iOS 16+ — native reply handler returns a Promise
                  return handler.postMessage({ event: eventName })
                    .then(v => (v == null ? null : v))
                    .catch(e => {
                      console.error('[OF] getAccessToken bridge error', e);
                      return null;
                    });
                } catch (e) {
                  console.error('[OF] getAccessToken bridge error (outer)', e);
                  return Promise.resolve(null);
                }
              };
            })();
        """
        // Compose the script, inserting helper before storage
        return """
        \(authBridgeHelper)
            const storage = new KeychainStorage();
            const openfort = new Openfort({
                baseConfiguration: {
                    publishableKey: '\(config.openfortPublishableKey)',
                    nativeAppIdentifier: '\(nativeAppIdentifier)',
                },
                shieldConfiguration: {
                    shieldPublishableKey: '\(config.shieldPublishableKey)',
                    debug: \(debugValue ? "true" : "false")
                },
                overrides: {
        \(overridesString)
                },
        \(thirdPartyAuthBlock.isEmpty ? "" : "                \(thirdPartyAuthBlock)")
            });
            
            window.openfort = openfort;
        """
    }
}
