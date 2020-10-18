import PromiseKit

@objc(LKPushNotificationManager)
public final class LokiPushNotificationManager : NSObject {

    // MARK: Settings
    #if DEBUG
    private static let server = "https://live.apns.getsession.org"
    #else
    private static let server = "https://live.apns.getsession.org"
    #endif
    internal static let pnServerPublicKey = "642a6585919742e5a2d4dc51244964fbcd8bcab2b75612407de58b810740d049"
    private static let maxRetryCount: UInt = 4
    private static let tokenExpirationInterval: TimeInterval = 12 * 60 * 60

    public enum ClosedGroupOperation: String {
        case subscribe = "subscribe_closed_group"
        case unsubscribe = "unsubscribe_closed_group"
    }

    // MARK: Initialization
    private override init() { }

    // MARK: Registration
    /// Unregisters the user from push notifications. Only the user's device token is needed for this.
    static func unregister(with token: Data, isForcedUpdate: Bool) -> Promise<Void> {
        let hexEncodedToken = token.toHexString()
        let parameters = [ "token" : hexEncodedToken ]
        let url = URL(string: "\(server)/unregister")!
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json" ]
        let promise: Promise<Void> = attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global()) {
            OnionRequestAPI.sendOnionRequest(request, to: server, using: pnServerPublicKey).map2 { response in
                guard let json = response["body"] as? JSON else {
                    return print("[Loki] Couldn't unregister from push notifications.")
                }
                guard json["code"] as? Int != 0 else {
                    return print("[Loki] Couldn't unregister from push notifications due to error: \(json["message"] as? String ?? "nil").")
                }
            }
        }
        promise.catch2 { error in
            print("[Loki] Couldn't unregister from push notifications.")
        }
        // Unsubscribe from all closed groups
        Storage.getUserClosedGroupPublicKeys().forEach { closedGroup in
            performOperation(.unsubscribe, for: closedGroup, publicKey: getUserHexEncodedPublicKey())
        }
        return promise
    }

    /// Unregisters the user from push notifications. Only the user's device token is needed for this.
    @objc(unregisterWithToken:isForcedUpdate:)
    static func objc_unregister(with token: Data, isForcedUpdate: Bool) -> AnyPromise {
        return AnyPromise.from(unregister(with: token, isForcedUpdate: isForcedUpdate))
    }

    /// Registers the user for push notifications. Requires the user's device
    /// token and their Session ID.
    static func register(with token: Data, publicKey: String, isForcedUpdate: Bool) -> Promise<Void> {
        let hexEncodedToken = token.toHexString()
        let userDefaults = UserDefaults.standard
        let oldToken = userDefaults[.deviceToken]
        let lastUploadTime = userDefaults[.lastDeviceTokenUpload]
        let now = Date().timeIntervalSince1970
        guard isForcedUpdate || hexEncodedToken != oldToken || now - lastUploadTime > tokenExpirationInterval else {
            print("[Loki] Device token hasn't changed or expired; no need to re-upload.")
            return Promise<Void> { $0.fulfill(()) }
        }
        let parameters = [ "token" : hexEncodedToken, "pubKey" : publicKey]
        let url = URL(string: "\(server)/register")!
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json" ]
        let promise: Promise<Void> = attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global()) {
            OnionRequestAPI.sendOnionRequest(request, to: server, using: pnServerPublicKey).map2 { response in
                guard let json = response["body"] as? JSON else {
                    return print("[Loki] Couldn't register device token.")
                }
                guard json["code"] as? Int != 0 else {
                    return print("[Loki] Couldn't register device token due to error: \(json["message"] as? String ?? "nil").")
                }
                userDefaults[.deviceToken] = hexEncodedToken
                userDefaults[.lastDeviceTokenUpload] = now
                userDefaults[.isUsingFullAPNs] = true
            }
        }
        promise.catch2 { error in
            print("[Loki] Couldn't register device token.")
        }
        // Subscribe to all closed groups
        Storage.getUserClosedGroupPublicKeys().forEach { closedGroup in
            performOperation(.subscribe, for: closedGroup, publicKey: publicKey)
        }
        return promise
    }

    /// Registers the user for push notifications. Requires the user's device
    /// token and their Session ID.
    @objc(registerWithToken:hexEncodedPublicKey:isForcedUpdate:)
    static func objc_register(with token: Data, publicKey: String, isForcedUpdate: Bool) -> AnyPromise {
        return AnyPromise.from(register(with: token, publicKey: publicKey, isForcedUpdate: isForcedUpdate))
    }
    
    static func performOperation(_ operation: ClosedGroupOperation, for closedGroupPublicKey: String, publicKey: String) -> Promise<Void> {
        let isUsingFullAPNs = UserDefaults.standard[.isUsingFullAPNs]
        guard isUsingFullAPNs else { return Promise<Void> { $0.fulfill(()) } }
        let parameters = [ "closedGroupPublicKey" : closedGroupPublicKey, "pubKey" : publicKey]
        let url = URL(string: "\(server)/\(operation.rawValue)")!
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json" ]
        let promise: Promise<Void> = attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global()) {
            OnionRequestAPI.sendOnionRequest(request, to: server, using: pnServerPublicKey).map2 { response in
                guard let json = response["body"] as? JSON else {
                    return print("[Loki] Couldn't subscribe/unsubscribe closed group: \(closedGroupPublicKey).")
                }
                guard json["code"] as? Int != 0 else {
                    return print("[Loki] Couldn't subscribe/unsubscribe for closed group: \(closedGroupPublicKey) due to error: \(json["message"] as? String ?? "nil").")
                }
            }
        }
        promise.catch2 { error in
            print("[Loki] Couldn't subscribe/unsubscribe closed group: \(closedGroupPublicKey).")
        }
        return promise
    }
    
    static func notify(for signalMessage: SignalMessage) -> Promise<Void> {
        let message = LokiMessage.from(signalMessage: signalMessage)!
        let parameters = [ "data" : message.data.description, "send_to" : message.recipientPublicKey]
        let url = URL(string: "\(server)/notify")!
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json" ]
        let promise: Promise<Void> = attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global()) {
            OnionRequestAPI.sendOnionRequest(request, to: server, using: pnServerPublicKey).map2 { response in
                guard let json = response["body"] as? JSON else {
                    return print("[Loki] Couldn't notify PN server.")
                }
                guard json["code"] as? Int != 0 else {
                    return print("[Loki] Couldn't notify PN server due to error: \(json["message"] as? String ?? "nil").")
                }
            }
        }
        promise.catch2 { error in
            print("[Loki] Couldn't notify PN server.")
        }
        return promise
    }

    @objc(notifyForMessage:)
    static func objc_notify(for signalMessage: SignalMessage) -> AnyPromise {
        return AnyPromise.from(notify(for: signalMessage))
    }
}
