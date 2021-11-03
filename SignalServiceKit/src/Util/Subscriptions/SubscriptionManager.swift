//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PassKit

public class SubscriptionLevel: Comparable {
    public let level: UInt
    public let badge: ProfileBadge
    public let currency: [String: NSDecimalNumber]
    
    public init(level: UInt, jsonDictionary: [String : Any]) throws {
        self.level = level
        let params = ParamParser(dictionary: jsonDictionary)
        let badgeDict: [String: Any] = try params.required(key: "badge")
        badge = try ProfileBadge(jsonDictionary: badgeDict)
        let currencyDict: [String: Any] = try params.required(key: "currencies")
        currency = currencyDict.compactMapValues {
            guard let int64Currency = $0 as? Int64 else {
                owsFailDebug("Failed to convert currency value")
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

    private static let subscriptionKVS = SDSKeyValueStore(collection: "SubscriptionKeyValueStore")
    private static let subscriberIDKey = "subscriberID"
    private static let subscriberCurrencyCodeKey = "subscriberCurrencyCode"
    
    //MARK: Subscription levels
    
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
                let subscriptions: [SubscriptionLevel] = try subscriptionDicts.compactMap { (subscriptionKey: String, value: Any) in
                    guard let subscriptionDict = value as? [String: Any] else {
                        return nil
                    }
                    
                    guard let level = UInt(subscriptionKey) else {
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
    
    //MARK: Subscription management
    
    public static var subscriberID: Data? {
        set {
            SDSDatabaseStorage.shared.write { transaction in
                self.setSubscriberID(newValue, transaction: transaction)
            }
        } get {
            return SDSDatabaseStorage.shared.read { transaction in
                self.getSubscriberID(transaction: transaction)
            }
        }
    }
    
    public static var subscriberCurrencyCode: String? {
        set {
            SDSDatabaseStorage.shared.write { transaction in
                self.setSubscriberCurrencyCode(newValue, transaction: transaction)
            }
        } get {
            return SDSDatabaseStorage.shared.read { transaction in
                self.getSubscriberCurrencyCode(transaction: transaction)
            }
        }
    }
    
    public static func getSubscriberID(transaction: SDSAnyReadTransaction) -> Data? {
        let subscriberID = SubscriptionManager.subscriptionKVS.getObject(
            forKey: SubscriptionManager.subscriberIDKey,
            transaction: transaction
        ) as? [Data] ?? []
        return subscriberID.first
    }
    
    public static func setSubscriberID(_ subscriberID: Data?, transaction: SDSAnyWriteTransaction) {
        SubscriptionManager.subscriptionKVS.setObject(subscriberID,
                                                      key: SubscriptionManager.subscriberIDKey,
                                                      transaction: transaction)
    }
    
    public static func getSubscriberCurrencyCode(transaction: SDSAnyReadTransaction) -> String? {
        let subscriberID = SubscriptionManager.subscriptionKVS.getObject(
            forKey: SubscriptionManager.subscriberIDKey,
            transaction: transaction
        ) as? [String] ?? []
        return subscriberID.first
    }
    
    public static func setSubscriberCurrencyCode(_ currencyCode: String?, transaction: SDSAnyWriteTransaction) {
        SubscriptionManager.subscriptionKVS.setObject(currencyCode,
                                                      key: SubscriptionManager.subscriberIDKey,
                                                      transaction: transaction)
    }
    

    public class func setupNewSubscriberID() throws -> Promise<Data> {

        guard let newSubscriberID = generateSubscriberID() else {
            throw OWSAssertionError("Unable to generate subscriberID")
        }
        
        let request = OWSRequestFactory.setSubscriptionIDRequest(newSubscriberID.asBase64Url)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode
            
            if let json = response.responseBodyJson as? [String: Any] {
                Logger.debug("Got response \(json)")
            }
            
            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }
            
            return newSubscriberID
        }
    }
    
    private class func generateSubscriberID() -> Data? {
        let bytes: [UInt8] = UUID().uInt8Array() + UUID().uInt8Array()
        let identifier = bytes.asData
        return identifier
    }
    
    public class func createPaymentMethod(for subscriberID: Data) throws -> Promise<String> {
        let request = OWSRequestFactory.subscriptionCreatePaymentMethodRequest(subscriberID.asBase64Url)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode

            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }
            
            guard let json = response.responseBodyJson as? [String: Any] else {
                throw OWSAssertionError("Unable to parse response body.")
            }
            
            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Missing or invalid response.")
            }
            
            do {
                let clientSecret: String = try parser.required(key: "clientSecret")
                return clientSecret
            } catch {
                throw OWSAssertionError("Missing clientID key")
            }
        }
    }
    
    public class func setDefaultPaymentMethod(for subscriberID: Data, paymentID: String) throws -> Promise<Void> {
        let request = OWSRequestFactory.subscriptionSetDefaultPaymentMethodRequest(subscriberID.asBase64Url, paymentID: paymentID)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode
            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }
        }
    }
    
    public class func setSubscription(for subscriberID: Data, subscription: SubscriptionLevel, currency: String) -> Promise<Void> {
        
        let subscriberID = subscriberID.asBase64Url
        let key = UUID().uInt8Array().asData.asBase64Url
        let level = String(subscription.level)
        let request = OWSRequestFactory.subscriptionSetSubscriptionLevelRequest(subscriberID, level: level, currency: currency, idempotencyKey: key)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode
            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }
        }
    }
}

extension UUID {
    public func uInt8Array() -> [UInt8]{
        let (u1,u2,u3,u4,u5,u6,u7,u8,u9,u10,u11,u12,u13,u14,u15,u16) = self.uuid
        return [u1,u2,u3,u4,u5,u6,u7,u8,u9,u10,u11,u12,u13,u14,u15,u16]
    }
}
