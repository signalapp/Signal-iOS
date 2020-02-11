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
        let lastUploadTime = UserDefaults.standard.integer(forKey: "lastUploadTime")
        let now = Int(Date().timeIntervalSince1970)
        if hexEncodedToken == oldToken && now - lastUploadTime < 48 * 60 * 60  {
            Logger.info("Token is not changed, no need to upload")
            return
        }
        // Send token to Loki server
        let parameters = [ "token" : hexEncodedToken ]
        let url = URL(string: "https://live.apns.getsession.org/register")!
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json" ]
        TSNetworkManager.shared().makeRequest(request, success: { _, response in
            guard let json = response as? JSON else { return }
            guard json["code"] as? Int != 0 else {
                return print("[Loki] An error occured during device token registration: \(json["message"] as? String ?? "nil").")
            }
            UserDefaults.standard.set(hexEncodedToken, forKey: "deviceToken")
            UserDefaults.standard.set(now, forKey: "lastUploadTime")
        }, failure: { _, error in
            print("[Loki] Couldn't register device token.")
        })
    }
}
