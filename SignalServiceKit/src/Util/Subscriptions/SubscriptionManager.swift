//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public class SubscriptionLevel: Comparable {
    public let level: Int
    public let badge: ProfileBadge
    public let currency: [String: NSDecimalNumber]
    
    public init(level: Int, jsonDictionary: [String : Any]) throws {
        self.level = level
        let params = ParamParser(dictionary: jsonDictionary)
        let badgeDict: [String: Any] = try params.required(key: "badge")
        badge = try ProfileBadge(jsonDictionary: badgeDict)
        let currencyDict: [String: Any] = try params.required(key: "currencies")
        currency = currencyDict.compactMapValues {
            guard let int64Currency = $0 as? Int64 else {
                return nil
            }
            return NSDecimalNumber(value: int64Currency)
        }
    }
    
    // MARK: Comparable
    
    public static func < (lhs: SubscriptionLevel, rhs: SubscriptionLevel) -> Bool {
        return lhs.level < rhs.level
    }
    
    public static func == (lhs: SubscriptionLevel, rhs: SubscriptionLevel) -> Bool {
        return lhs.level == rhs.level
    }
}

public class SubscriptionManager: NSObject {
    
    public class func getSubscriptions() -> Promise<[SubscriptionLevel]> {
        let request = OWSRequestFactory.subscriptionLevelsRequest()

        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            
            guard let json = response.responseBodyJson as? [String: Any] else {
                throw OWSAssertionError("Missing or invalid JSON.")
            }
            
            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Missing or invalid response.")
            }

            do {
                let subscriptionDicts: [String: Any] = try parser.required(key: "levels")
                let subscriptions: [SubscriptionLevel] = try subscriptionDicts.compactMap {
                    guard let subscriptionDict = $1 as? [String: Any] else {
                        return nil
                    }
                    
                    guard let level = Int($0) else {
                        throw OWSAssertionError("Unable to determine subscription level")
                    }

                    return try SubscriptionLevel(level: level, jsonDictionary: subscriptionDict)
                }
                return subscriptions.sorted()
            } catch {
                owsFailDebug("Unable to parse subscription levels, \(error)")
            }

            return []
        }
    }
    
}
