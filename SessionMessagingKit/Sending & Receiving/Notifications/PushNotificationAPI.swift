import SessionSnodeKit
import PromiseKit

@objc(LKPushNotificationAPI)
public final class PushNotificationAPI : NSObject {

    // MARK: Settings
    public static let server = "https://live.apns.getsession.org"
    public static let serverPublicKey = "642a6585919742e5a2d4dc51244964fbcd8bcab2b75612407de58b810740d049"
    private static let maxRetryCount: UInt = 4
    private static let tokenExpirationInterval: TimeInterval = 12 * 60 * 60

    @objc public enum ClosedGroupOperation : Int {
        case subscribe, unsubscribe
        
        public var endpoint: String {
            switch self {
            case .subscribe: return "subscribe_closed_group"
            case .unsubscribe: return "unsubscribe_closed_group"
            }
        }
    }

    // MARK: Initialization
    private override init() { }

    // MARK: Registration
    public static func unregister(_ token: Data) -> Promise<Void> {
        let hexEncodedToken = token.toHexString()
        let parameters = [ "token" : hexEncodedToken ]
        let url = URL(string: "\(server)/unregister")!
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json" ]
        let promise: Promise<Void> = attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global()) {
            OnionRequestAPI.sendOnionRequest(request, to: server, target: "/loki/v2/lsrpc", using: serverPublicKey).map2 { response in
                guard let json = response["body"] as? JSON else {
                    return SNLog("Couldn't unregister from push notifications.")
                }
                guard json["code"] as? Int != 0 else {
                    return SNLog("Couldn't unregister from push notifications due to error: \(json["message"] as? String ?? "nil").")
                }
            }
        }
        promise.catch2 { error in
            SNLog("Couldn't unregister from push notifications.")
        }
        // Unsubscribe from all closed groups
        Storage.shared.getUserClosedGroupPublicKeys().forEach { closedGroupPublicKey in
            performOperation(.unsubscribe, for: closedGroupPublicKey, publicKey: getUserHexEncodedPublicKey())
        }
        return promise
    }

    @objc(unregisterToken:)
    public static func objc_unregister(token: Data) -> AnyPromise {
        return AnyPromise.from(unregister(token))
    }

    public static func register(with token: Data, publicKey: String, isForcedUpdate: Bool) -> Promise<Void> {
        let hexEncodedToken = token.toHexString()
        let userDefaults = UserDefaults.standard
        let oldToken = userDefaults[.deviceToken]
        let lastUploadTime = userDefaults[.lastDeviceTokenUpload]
        let now = Date().timeIntervalSince1970
        guard isForcedUpdate || hexEncodedToken != oldToken || now - lastUploadTime > tokenExpirationInterval else {
            SNLog("Device token hasn't changed or expired; no need to re-upload.")
            return Promise<Void> { $0.fulfill(()) }
        }
        let parameters = [ "token" : hexEncodedToken, "pubKey" : publicKey ]
        let url = URL(string: "\(server)/register")!
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json" ]
        let promise: Promise<Void> = attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global()) {
            OnionRequestAPI.sendOnionRequest(request, to: server, target: "/loki/v2/lsrpc", using: serverPublicKey).map2 { response in
                guard let json = response["body"] as? JSON else {
                    return SNLog("Couldn't register device token.")
                }
                guard json["code"] as? Int != 0 else {
                    return SNLog("Couldn't register device token due to error: \(json["message"] as? String ?? "nil").")
                }
                userDefaults[.deviceToken] = hexEncodedToken
                userDefaults[.lastDeviceTokenUpload] = now
                userDefaults[.isUsingFullAPNs] = true
            }
        }
        promise.catch2 { error in
            SNLog("Couldn't register device token.")
        }
        // Subscribe to all closed groups
        Storage.shared.getUserClosedGroupPublicKeys().forEach { closedGroupPublicKey in
            performOperation(.subscribe, for: closedGroupPublicKey, publicKey: publicKey)
        }
        return promise
    }

    @objc(registerWithToken:hexEncodedPublicKey:isForcedUpdate:)
    public static func objc_register(with token: Data, publicKey: String, isForcedUpdate: Bool) -> AnyPromise {
        return AnyPromise.from(register(with: token, publicKey: publicKey, isForcedUpdate: isForcedUpdate))
    }

    @discardableResult
    public static func performOperation(_ operation: ClosedGroupOperation, for closedGroupPublicKey: String, publicKey: String) -> Promise<Void> {
        let isUsingFullAPNs = UserDefaults.standard[.isUsingFullAPNs]
        guard isUsingFullAPNs else { return Promise<Void> { $0.fulfill(()) } }
        let parameters = [ "closedGroupPublicKey" : closedGroupPublicKey, "pubKey" : publicKey ]
        let url = URL(string: "\(server)/\(operation.endpoint)")!
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json" ]
        let promise: Promise<Void> = attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global()) {
            OnionRequestAPI.sendOnionRequest(request, to: server, target: "/loki/v2/lsrpc", using: serverPublicKey).map2 { response in
                guard let json = response["body"] as? JSON else {
                    return SNLog("Couldn't subscribe/unsubscribe for closed group: \(closedGroupPublicKey).")
                }
                guard json["code"] as? Int != 0 else {
                    return SNLog("Couldn't subscribe/unsubscribe for closed group: \(closedGroupPublicKey) due to error: \(json["message"] as? String ?? "nil").")
                }
            }
        }
        promise.catch2 { error in
            SNLog("Couldn't subscribe/unsubscribe for closed group: \(closedGroupPublicKey).")
        }
        return promise
    }
    
    @objc(performOperation:forClosedGroupWithPublicKey:userPublicKey:)
    public static func objc_performOperation(_ operation: ClosedGroupOperation, for closedGroupPublicKey: String, publicKey: String) -> AnyPromise {
        return AnyPromise.from(performOperation(operation, for: closedGroupPublicKey, publicKey: publicKey))
    }
}
