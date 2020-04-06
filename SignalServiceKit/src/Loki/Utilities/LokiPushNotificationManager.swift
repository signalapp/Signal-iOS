
@objc(LKPushNotificationManager)
final class LokiPushNotificationManager : NSObject {

    // MARK: Settings
    #if DEBUG
    private static let server = "https://dev.apns.getsession.org/"
    #else
    private static let server = "https://live.apns.getsession.org/"
    #endif
    private static let tokenExpirationInterval: TimeInterval = 2 * 24 * 60 * 60

    // MARK: Initialization
    private override init() { }

    // MARK: Registration
    /// Registers the user for silent push notifications (that then trigger the app
    /// into fetching messages). Only the user's device token is needed for this.
    @objc(registerWithToken:)
    static func register(with token: Data) {
        let hexEncodedToken = token.toHexString()
        let userDefaults = UserDefaults.standard
        let oldToken = userDefaults[.deviceToken]
        let lastUploadTime = userDefaults[.lastDeviceTokenUpload]
        let isUsingFullAPNs = userDefaults[.isUsingFullAPNs]
        let now = Date().timeIntervalSince1970
        guard hexEncodedToken != oldToken || now - lastUploadTime < tokenExpirationInterval else {
            return print("[Loki] Device token hasn't changed; no need to re-upload.")
        }
        guard !isUsingFullAPNs else {
            return print("[Loki] Using full APNs; ignoring call to register(with:).")
        }
        let parameters = [ "token" : hexEncodedToken ]
        let url = URL(string: server + "register")!
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json" ]
        TSNetworkManager.shared().makeRequest(request, success: { _, response in
            guard let json = response as? JSON else {
                return print("[Loki] Couldn't register device token.")
            }
            guard json["code"] as? Int != 0 else {
                return print("[Loki] Couldn't register device token due to error: \(json["message"] as? String ?? "nil").")
            }
            userDefaults[.deviceToken] = hexEncodedToken
            userDefaults[.lastDeviceTokenUpload] = now
            userDefaults[.isUsingFullAPNs] = false
        }, failure: { _, error in
            print("[Loki] Couldn't register device token.")
        })
    }

    /// Registers the user for normal push notifications. Requires the user's device
    /// token and their Session ID.
    @objc(registerWithToken:hexEncodedPublicKey:)
    static func register(with token: Data, hexEncodedPublicKey: String) {
        let hexEncodedToken = token.toHexString()
        let userDefaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        let parameters = [ "token" : hexEncodedToken, "pubKey" : hexEncodedPublicKey]
        let url = URL(string: server + "register")!
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json" ]
        TSNetworkManager.shared().makeRequest(request, success: { _, response in
            guard let json = response as? JSON else {
                return print("[Loki] Couldn't register device token.")
            }
            guard json["code"] as? Int != 0 else {
                return print("[Loki] Couldn't register device token due to error: \(json["message"] as? String ?? "nil").")
            }
            userDefaults[.deviceToken] = hexEncodedToken
            userDefaults[.lastDeviceTokenUpload] = now
            userDefaults[.isUsingFullAPNs] = true
        }, failure: { _, error in
            print("[Loki] Couldn't register device token.")
        })
    }
    
    @objc(acknowledgeDeliveryForMessageWithHash:expiration:hexEncodedPublicKey:)
    static func acknowledgeDelivery(forMessageWithHash hash: String, expiration: Int, hexEncodedPublicKey: String) {
        let parameters: JSON = [ "lastHash" : hash, "pubKey" : hexEncodedPublicKey, "expiration" : expiration]
        let url = URL(string: server + "acknowledge_message_delivery")!
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json" ]
        TSNetworkManager.shared().makeRequest(request, success: { _, response in
            guard let json = response as? JSON else {
                return print("[Loki] Couldn't acknowledge delivery for message with hash: \(hash).")
            }
            guard json["code"] as? Int != 0 else {
                return print("[Loki] Couldn't acknowledge delivery for message with hash: \(hash) due to error: \(json["message"] as? String ?? "nil").")
            }
        }, failure: { _, error in
            print("[Loki] Couldn't acknowledge delivery for message with hash: \(hash).")
        })
    }
}
