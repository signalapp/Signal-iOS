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
    /** This method is for users to register for Silent Push Notification.
        We only need the device token to make the SPN work.*/
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
            return print("[Loki] Using full APNs; no need to upload device token.")
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
    
    /** This method is for users to register for Normal Push Notification.
        We need the device token and user's public key (session id) to make the NPN work.*/
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
    static func acknowledgeDelivery(forMessageWithHash hash: String, expiration:Int, hexEncodedPublicKey: String) {
        let parameters: JSON = [ "lastHash" : hash,
                                           "pubKey" : hexEncodedPublicKey,
                                           "expiration": expiration]
        let url = URL(string: server + "acknowledge_message_delivery")!
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json" ]
        TSNetworkManager.shared().makeRequest(request, success: { _, response in
            guard let json = response as? JSON else {
                return print("[Loki] Couldn't acknowledge the delivery for message with last hash: " + hash)
            }
            guard json["code"] as? Int != 0 else {
                return print("[Loki] Couldn't acknowledge the delivery for message due to error: \(json["message"] as? String ?? "nil").")
            }
        }, failure: { _, error in
            print("[Loki] Couldn't acknowledge the delivery for message with last hash: " + hash)
        })
    }
}
