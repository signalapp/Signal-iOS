import UIKit

// Ideally this should be in SignalServiceKit, but somehow linking fails when it is.

@objc(LKPushNotificationManager)
final class LokiPushNotificationManager : NSObject {
    
    @objc static let shared = LokiPushNotificationManager()
    
    private override init() { super.init() }
    
    @objc(registerWithToken:)
    func register(with token: Data) {
        let hexEncodedToken = token.map { String(format: "%02.2hhx", $0) }.joined()
        let oldToken = UserDefaults.standard.string(forKey: "deviceToken")
        let lastUploadTime = UserDefaults.standard.double(forKey: "lastDeviceTokenUploadTime")
        let now = Date().timeIntervalSince1970
        if hexEncodedToken == oldToken && now - lastUploadTime < 2 * 24 * 60 * 60  {
            print("[Loki] Device token hasn't changed; no need to upload.")
            return
        }
        // Send token to Loki server
        let parameters = [ "token" : hexEncodedToken ]
//        let url = URL(string: "https://live.apns.getsession.org/register")!
        let url = URL(string: "https://dev.apns.getsession.org/register")!
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json" ]
        TSNetworkManager.shared().makeRequest(request, success: { _, response in
            guard let json = response as? JSON else { return }
            guard json["code"] as? Int != 0 else {
                return print("[Loki] An error occured during device token registration: \(json["message"] as? String ?? "nil").")
            }
            UserDefaults.standard.set(hexEncodedToken, forKey: "deviceToken")
            UserDefaults.standard.set(now, forKey: "lastDeviceTokenUploadTime")
        }, failure: { _, error in
            print("[Loki] Couldn't register device token.")
        })
    }
}
