//
//  WebView.swift
//  OpenfortAuthorization
//
//  Created by Pavel Gurkovskii on 2025-06-22.
//

import SwiftUI
import WebKit

internal class OFWebView: WKWebView {
    let fileUrl: URL
    let delegate: WKNavigationDelegate?
    let scriptMessageHandler: WKScriptMessageHandler?
    let provider: String?
    
    init(fileUrl: URL, delegate: WKNavigationDelegate?, scriptMessageHandler: WKScriptMessageHandler?, provider: String? = nil, getAccessToken: (() async throws -> String?)? = nil) {
        self.fileUrl = fileUrl
        self.delegate = delegate
        self.scriptMessageHandler = scriptMessageHandler
        self.provider = provider
        
        // Configure webpage preferences for JavaScript
        let webPagePreferences = WKWebpagePreferences()
        webPagePreferences.allowsContentJavaScript = true

        // Configure the user content controller (message handler for JS-to-Swift bridge)
        let userContentController = WKUserContentController()
        if let messageHandler = scriptMessageHandler {
            userContentController.add(messageHandler, name: "userHandler")
            userContentController.add(messageHandler, name: "secureHandler")
        }
        if let getAccessToken = getAccessToken {
            let authHandler = OFAuthReplyHandler()
            authHandler.getAccessToken = {
                try await getAccessToken()
            }
            userContentController.addScriptMessageHandler(authHandler, contentWorld: .page, name: "authHandler")
        }
        
        func addScript(named name: String, injectionTime: WKUserScriptInjectionTime) {
            if let scriptPath = Bundle.module.url(forResource: name, withExtension: "js"),
               let scriptContent = try? String(contentsOf: scriptPath) {
                let userScript = WKUserScript(source: scriptContent, injectionTime: injectionTime, forMainFrameOnly: false)
                userContentController.addUserScript(userScript)
            }
        }
        
        // openfort must be available before openfort-sync runs, hence earlier injection for the first three scripts
        addScript(named: "storage", injectionTime: .atDocumentStart)
        addScript(named: "securestorage", injectionTime: .atDocumentStart)
        addScript(named: "openfort", injectionTime: .atDocumentStart)
        addScript(named: "utils", injectionTime: .atDocumentStart)
        addScript(named: "openfort-sync", injectionTime: .atDocumentStart)

        let script = OFConfig.openfortSyncScript(provider: provider)
        let userScript = WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
            userContentController.addUserScript(userScript)
        

        // Configure the web view
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = webPagePreferences
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        config.userContentController = userContentController

        // Call the designated initializer for WKWebView (super)
        super.init(frame: .zero, configuration: config)

        // Configure 'self'
        self.navigationDelegate = delegate

        // Load the local file URL
        self.loadFileURL(fileUrl, allowingReadAccessTo: fileUrl.deletingLastPathComponent())
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
