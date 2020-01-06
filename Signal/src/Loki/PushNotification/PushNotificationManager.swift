//
//  Copyright (c) 2018 Loki Messenger. All rights reserved.
//  This file is for silent push notification
//  Created by Ryan Zhao
// 

import UIKit

@objc(LKPushNotificationManager)
class PushNotificationManager: NSObject {
    
    static let shared = PushNotificationManager()
    
    private override init() {
        super.init()
    }
    
    @objc
    class func sharedInstance() -> PushNotificationManager {
        return PushNotificationManager.shared
    }
    
    @objc
    func registerNotification(token: Data) {
        let deviceToken = token.map { String(format: "%02.2hhx", $0) }.joined()
        print("Device Token: (\(deviceToken))")
        /** send token to Loki centralized server  **/
        let parameters = [ "token" : deviceToken ]
        let url = URL(string: "http://88.99.14.72:5000/register")!
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json"]
        TSNetworkManager.shared().makeRequest(
            request,
            success: { (_, response: Any?) -> Void in
                if let responseDictionary = response as? [String: Any] {
                    if responseDictionary["code"] as? Int == 0 {
                        print("[Loki] error occured during sending device token \(String(describing: responseDictionary["message"] as? String))")
                    }
                }
        },
            failure: { (_, error: Error?) -> Void in
                print("[Loki] Couldn't send the device token to the centralized server")
        })
    }
    
    // TODO: Move the fetch message fucntion here?
    
}
