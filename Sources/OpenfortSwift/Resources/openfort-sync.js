//
//  openfort-sync.js
//  OpenfortSwift
//
//  Created by Pavel Gurkovskii on 2025-06-30.
//

function handleResult(method, promiseOrValue) {
    try {
        var promise = (promiseOrValue && typeof promiseOrValue.then === 'function')
            ? promiseOrValue
            : Promise.resolve(promiseOrValue);
        promise
            .then(result => {
                window.webkit.messageHandlers.userHandler.postMessage({ method: method, success: true, data: result });
            })
            .catch(error => {
                window.webkit.messageHandlers.userHandler.postMessage({ method: method, success: false, error: error && error.message ? error.message : String(error) });
            });
    } catch (syncError) {
        window.webkit.messageHandlers.userHandler.postMessage({ method: method, success: false, error: syncError && syncError.message ? syncError.message : String(syncError) });
    }
}

function safeCall(method, fn) {
    try {
        handleResult(method, fn());
    } catch (e) {
        window.webkit.messageHandlers.userHandler.postMessage({ method: method, success: false, error: e && e.message ? e.message : String(e) });
    }
}

// AuthInstance sync methods

window.logInWithEmailPasswordSync = function({ email, password }) {
    handleResult('logInWithEmailPassword', window.openfort.authInstance.logInWithEmailPassword({ email, password }));
};

window.signUpGuestSync = function() {
    handleResult('signUpGuest', window.openfort.authInstance.signUpGuest());
};

window.signUpWithEmailPasswordSync = function({ email, password, name }) {
    const options = name ? { data: { name } } : undefined;
    handleResult(
        'signUpWithEmailPassword',
        window.openfort.authInstance.signUpWithEmailPassword({
            email,
            password,
            options
        })
    );
};

window.resetPasswordSync = function({ password, token }) {
    handleResult('resetPassword', window.openfort.authInstance.resetPassword({
        password,
        token
    }));
};

window.requestResetPasswordSync = function({ email, redirectUrl }) {
    handleResult('requestResetPassword', window.openfort.authInstance.requestResetPassword({
        email,
        redirectUrl
    }));
};

window.requestEmailVerificationSync = function({ email, redirectUrl }) {
    handleResult('requestEmailVerification', window.openfort.authInstance.requestEmailVerification({
        email,
        redirectUrl
    }));
};

window.verifyEmailSync = function({ token, callbackURL }) {
    handleResult('verifyEmail', window.openfort.authInstance.verifyEmail({
        token,
        callbackURL
    }));
};

window.initOAuthSync = function({ provider, options }) {
    handleResult('initOAuth', window.openfort.authInstance.initOAuth({
        provider,
        options
    }));
};

window.unlinkOAuthSync = function({ provider, authToken }) {
    handleResult('unlinkOAuth', window.openfort.authInstance.unlinkOAuth({
        provider,
        authToken
    }));
};

window.loginWithIdTokenSync = function({ provider, token }) {
    handleResult('loginWithIdToken', window.openfort.authInstance.loginWithIdToken({
        provider,
        token
    }));
};

window.linkWalletSync = function({ signature, message, walletClientType, connectorType, authToken }) {
    handleResult('linkWallet', window.openfort.authInstance.linkWallet({
        signature,
        message,
        walletClientType,
        connectorType,
        authToken
    }));
};

window.logoutSync = function() {
    handleResult('logout', window.openfort.authInstance.logout());
};

window.initLinkOAuthSync = function({ provider, options }) {
    handleResult('initLinkOAuth', window.openfort.authInstance.initLinkOAuth({
        provider,
        options
    }));
};

window.poolOAuthSync = function({ key }) {
    handleResult('poolOAuth', window.openfort.authInstance.poolOAuth({ key }));
};

window.initSIWESync = function({ address }) {
    handleResult('initSIWE', window.openfort.authInstance.initSiwe({
        address
    }));
};

window.unlinkWalletSync = function({ address, authToken }) {
    handleResult('unlinkWallet', window.openfort.authInstance.unlinkWallet({
        address,
        authToken
    }));
};

window.authenticateWithSIWESync = function({ signature, message, walletClientType, connectorType }) {
    handleResult('authenticateWithSIWE', window.openfort.authInstance.loginWithSiwe({
        signature,
        message,
        walletClientType,
        connectorType
    }));
};

window.storeCredentialsSync = function({ token, userId }) {
    handleResult(
        'storeCredentials',
        window.openfort.authInstance.storeCredentials({
            token,
            userId
        })
    );
};

// Email OTP sync methods

window.requestEmailOtpSync = function({ email }) {
    handleResult('requestEmailOtp', window.openfort.authInstance.requestEmailOtp({ email }));
};

window.logInWithEmailOtpSync = function({ email, otp }) {
    handleResult('logInWithEmailOtp', window.openfort.authInstance.logInWithEmailOtp({ email, otp }));
};

// Phone OTP sync methods

window.requestPhoneOtpSync = function({ phoneNumber }) {
    handleResult('requestPhoneOtp', window.openfort.authInstance.requestPhoneOtp({ phoneNumber }));
};

window.logInWithPhoneOtpSync = function({ phoneNumber, otp }) {
    handleResult('logInWithPhoneOtp', window.openfort.authInstance.logInWithPhoneOtp({ phoneNumber, otp }));
};

window.linkPhoneOtpSync = function({ phoneNumber, otp }) {
    handleResult('linkPhoneOtp', window.openfort.authInstance.linkPhoneOtp({ phoneNumber, otp }));
};

// Email verification OTP sync method

window.verifyEmailOtpSync = function({ email, otp }) {
    handleResult('verifyEmailOtp', window.openfort.authInstance.verifyEmailOtp({ email, otp }));
};

// SIWE authentication sync methods

window.loginWithSiweSync = function({ signature, message, walletClientType, connectorType, address }) {
    handleResult('loginWithSiwe', window.openfort.authInstance.loginWithSiwe({
        signature,
        message,
        walletClientType,
        connectorType,
        address
    }));
};

window.initLinkSiweSync = function({ address }) {
    handleResult('initLinkSiwe', window.openfort.authInstance.initLinkSiwe({ address }));
};

window.linkWithSiweSync = function({ signature, message, walletClientType, connectorType, address, chainId }) {
    handleResult('linkWithSiwe', window.openfort.authInstance.linkWithSiwe({
        signature,
        message,
        walletClientType,
        connectorType,
        address,
        chainId
    }));
};

// Add email sync method

window.addEmailSync = function({ email, callbackURL }) {
    handleResult('addEmail', window.openfort.authInstance.addEmail({ email, callbackURL }));
};

// EmbeddedWalletInstance sync methods

window.signTypedDataSync = function({ domain, types, message }) {
    handleResult('signTypedData', window.openfort.embeddedWalletInstance.signTypedData(domain, types, message));
};

window.getSync = function() {
    handleResult('get', window.openfort.embeddedWalletInstance.get());
};

window.getEthereumProviderSync = function({ options } = {}) {
    handleResult('getEthereumProvider', window.openfort.embeddedWalletInstance.getEthereumProvider(options));
};

window.configureSync = function({ params }) {
    safeCall('configure', () => window.openfort.embeddedWalletInstance.configure(params));
};

window.createSync = function({ params }) {
    handleResult('create', window.openfort.embeddedWalletInstance.create(params));
};

window.recoverSync = function({ params }) {
    handleResult('recover', window.openfort.embeddedWalletInstance.recover(params));
};

window.exportPrivateKeySync = function() {
    handleResult('exportPrivateKey', window.openfort.embeddedWalletInstance.exportPrivateKey());
};

window.listSync = function() {
    handleResult('list', window.openfort.embeddedWalletInstance.list());
};

window.pingSync = function({ delay }) {
    handleResult('ping', window.openfort.embeddedWalletInstance.ping(delay));
};

window.signMessageSync = function({ message, options }) {
    handleResult('signMessage', window.openfort.embeddedWalletInstance.signMessage(message, options));
};

window.setRecoveryMethodSync = function({ previousRecovery, newRecovery }) {
    handleResult('setRecoveryMethod', window.openfort.embeddedWalletInstance.setRecoveryMethod(
        previousRecovery,
        newRecovery
    ));
};

window.getEmbeddedStateSync = function() {
    handleResult('getEmbeddedState', window.openfort.embeddedWalletInstance.getEmbeddedState());
};

// Embedded-state change watcher.
//
// openfort-js has no dedicated "embedded state changed" event: getEmbeddedState() is a
// pure value computed from storage (UNAUTHENTICATED / EMBEDDED_SIGNER_NOT_CONFIGURED /
// READY). What it *does* expose is a public lifecycle emitter on window.openfort.eventEmitter
// that fires on exactly the events that move that value: auth success/failure, logout,
// embedded wallet created/recovered, and account switch. We subscribe to those, re-read the
// state on each, and push it to native — turning a 1s busy poll into event-driven updates.
//
// One transition isn't covered by an event: embeddedWalletInstance.configure() persists the
// signer (NOT_CONFIGURED -> READY) without emitting. The native side closes that gap with a
// short bounded poll after each push; this watcher only handles the event-driven majority.
window.__ofWatchEmbeddedState = function() {
    if (window.__ofEmbeddedStateWatching) {
        return true;
    }
    var of = window.openfort;
    if (!of || !of.eventEmitter || typeof of.eventEmitter.on !== 'function') {
        // Bridge not fully constructed yet; retry briefly. The native side also runs a
        // bounded backstop poll, so this is just to wire events as early as possible.
        if ((window.__ofWatchRetries = (window.__ofWatchRetries || 0) + 1) <= 50) {
            setTimeout(window.__ofWatchEmbeddedState, 100);
        }
        return false;
    }
    window.__ofEmbeddedStateWatching = true;

    var push = function() {
        try {
            Promise.resolve(of.embeddedWalletInstance.getEmbeddedState())
                .then(function(state) {
                    window.webkit.messageHandlers.userHandler.postMessage({
                        method: 'embeddedStateChanged', success: true, data: state
                    });
                })
                .catch(function() { /* transient read error; native poll backstops it */ });
        } catch (e) { /* ignore */ }
    };

    ['onAuthSuccess', 'onAuthFailure', 'onLogout',
     'onEmbeddedWalletCreated', 'onEmbeddedWalletRecovered',
     'onSwitchAccount'].forEach(function(evt) {
        try { of.eventEmitter.on(evt, push); } catch (e) { /* unknown event: skip */ }
    });

    // Emit the current state once so native starts from the real value, not a guess.
    push();
    return true;
};

window.getURLSync = function() {
    handleResult('getURL', window.openfort.embeddedWalletInstance.getURL());
};

// ProxyInstance sync methods

window.sendSignatureTransactionIntentRequestSync = function({ transactionIntentId, signableHash = null, signature = null, optimistic = false }) {
    handleResult(
        'sendSignatureTransactionIntentRequest',
        window.openfort.proxyInstance.sendSignatureTransactionIntentRequest({ transactionIntentId, signableHash, signature, optimistic })
    );
};

window.sendSignatureSessionRequestSync = function({ sessionId, signature, optimistic }) {
    handleResult(
        'sendSignatureSessionRequest',
        window.openfort.proxyInstance.sendSignatureSessionRequest({ sessionId, signature, optimistic })
    );
};

// UserInstance sync methods

window.getUserSync = function() {
    safeCall('getUserInstance', () => window.openfort.userInstance.get());
};

// Openfort sync methods

window.getAccessTokenSync = function() {
    handleResult('getAccessToken', window.openfort.getAccessToken());
};

window.validateAndRefreshTokenSync = function({ forceRefresh } = {}) {
    handleResult('validateAndRefreshToken', window.openfort.validateAndRefreshToken(forceRefresh));
};

// Funding (cross-chain deposit) sync methods
//
// These drive the public `window.openfort.funding` namespace (openfort-js >= 1.5.0), which
// authenticates with the project publishable key and needs no logged-in user. The Swift
// `OFFunding` hook owns the poll loop, so the bridge only exposes the atomic primitives
// (create / setPaymentMethod / get / payLink / chains), not the one-call `funding.fund()`.

window.fundingCreateSessionSync = function({ target, amountUnits, metadata, externalId, strict, paymentMethod }) {
    handleResult('fundingCreateSession', window.openfort.funding.sessions.create({
        target, amountUnits, metadata, externalId, strict, paymentMethod
    }));
};

window.fundingSetPaymentMethodSync = function({ sessionId, paymentMethod, clientSecret }) {
    handleResult('fundingSetPaymentMethod', window.openfort.funding.sessions.setPaymentMethod(sessionId, {
        paymentMethod, clientSecret
    }));
};

window.fundingGetSessionSync = function({ sessionId, clientSecret }) {
    handleResult('fundingGetSession', window.openfort.funding.sessions.get(sessionId, { clientSecret }));
};

window.fundingPayLinkSync = function({ sessionId, clientSecret, amount, asset }) {
    handleResult('fundingPayLink', window.openfort.funding.payLink({ sessionId, clientSecret, amount, asset }));
};

window.fundingChainsSync = function() {
    handleResult('fundingChains', window.openfort.funding.chains());
};
