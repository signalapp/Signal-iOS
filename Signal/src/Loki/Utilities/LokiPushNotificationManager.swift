import UIKit

// Ideally this should be in SignalServiceKit, but somehow linking fails when it is.

@objc(LKPushNotificationManager)
final class LokiPushNotificationManager : NSObject {
    
    @objc static let shared = LokiPushNotificationManager()
    
    private override init() { super.init() }
    
    @objc(registerWithToken:)
    func register(with token: Data) {
        let hexEncodedToken = token.map { String(format: "%02.2hhx", $0) }.joined()
        let userDefaults = UserDefaults.standard
        let oldToken = userDefaults[.deviceToken]
        let lastUploadTime = userDefaults[.lastDeviceTokenUpload]
        let applyNormalNotification = userDefaults[.applyNormalNotification]
        let now = Date().timeIntervalSince1970
        if hexEncodedToken == oldToken && now - lastUploadTime < 2 * 24 * 60 * 60  {
            print("[Loki] Device token hasn't changed; no need to upload.")
            return
        }
        if applyNormalNotification {
            print("[Loki] Using normal notification; no need to upload.")
            return
        }
        // Send token to Loki server
        let parameters = [ "token" : hexEncodedToken ]
        #if DEBUG
        let url = URL(string: "https://dev.apns.getsession.org/register")!
        #else
        let url = URL(string: "https://live.apns.getsession.org/register")!
        #endif
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json" ]
        TSNetworkManager.shared().makeRequest(request, success: { _, response in
            guard let json = response as? JSON else { return }
            guard json["code"] as? Int != 0 else {
                return print("[Loki] An error occured during device token registration: \(json["message"] as? String ?? "nil").")
            }
            userDefaults[.deviceToken] = hexEncodedToken
            userDefaults[.lastDeviceTokenUpload] = now
            userDefaults[.applyNormalNotification] = false
        }, failure: { _, error in
            print("[Loki] Couldn't register device token.")
        })
    }
    
    @objc(registerWithToken: pubkey:)
    func register(with token: Data, pubkey: String) {
        let hexEncodedToken = token.map { String(format: "%02.2hhx", $0) }.joined()
        let userDefaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        // Send token to Loki server
        let parameters = [ "token" : hexEncodedToken,
                           "pubKey": pubkey]
        #if DEBUG
        let url = URL(string: "https://dev.apns.getsession.org/register")!
        #else
        let url = URL(string: "https://live.apns.getsession.org/register")!
        #endif
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json" ]
        TSNetworkManager.shared().makeRequest(request, success: { _, response in
            guard let json = response as? JSON else { return }
            guard json["code"] as? Int != 0 else {
                return print("[Loki] An error occured during device token registration: \(json["message"] as? String ?? "nil").")
            }
            userDefaults[.deviceToken] = hexEncodedToken
            userDefaults[.lastDeviceTokenUpload] = now
            userDefaults[.applyNormalNotification] = true
        }, failure: { _, error in
            print("[Loki] Couldn't register device token.")
        })
    }
}
