
// Ideally this should be in SignalServiceKit, but somehow linking fails when it is.

@objc(LKPushNotificationManager)
final class LokiPushNotificationManager : NSObject {

    // MARK: Settings
    #if DEBUG
    private static let url = URL(string: "https://dev.apns.getsession.org/register")!
    #else
    private static let url = URL(string: "https://live.apns.getsession.org/register")!
    #endif
    private static let tokenExpirationInterval: TimeInterval = 2 * 24 * 60 * 60

    // MARK: Initialization
    private override init() { }

    // MARK: Registration
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
    
    @objc(registerWithToken:hexEncodedPublicKey:)
    static func register(with token: Data, hexEncodedPublicKey: String) {
        let hexEncodedToken = token.toHexString()
        let userDefaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        let parameters = [ "token" : hexEncodedToken, "pubKey" : hexEncodedPublicKey]
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
}
