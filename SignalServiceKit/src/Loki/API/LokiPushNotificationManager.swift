import UIKit

@objc(LKPushNotificationManager)
final class LokiPushNotificationManager : NSObject {
    
    @objc static let shared = LokiPushNotificationManager()
    
    private override init() { super.init() }
    
    @objc(registerWithToken:)
    func register(with token: Data) {
        let hexEncodedToken = token.map { String(format: "%02.2hhx", $0) }.joined()
        print("Registering device token: (\(hexEncodedToken))")
        // Send token to Loki server
        let parameters = [ "token" : hexEncodedToken ]
        let url = URL(string: "http://88.99.14.72:5000/register")!
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json" ]
        TSNetworkManager.shared().makeRequest(request, success: { _, response in
            guard let json = response as? JSON else { return }
            guard json["code"] as? Int != 0 else {
                return print("[Loki] An error occured during device token registration: \(json["message"] as? String ?? "nil").")
            }
        }, failure: { _, error in
            print("[Loki] Couldn't register device token.")
        })
    }
}
