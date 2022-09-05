// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import GRDB
import PromiseKit
import SessionSnodeKit
import SessionUtilitiesKit

@objc(LKPushNotificationAPI)
public final class PushNotificationAPI : NSObject {
    struct RegistrationRequestBody: Codable {
        let token: String
        let pubKey: String?
    }
    
    struct NotifyRequestBody: Codable {
        enum CodingKeys: String, CodingKey {
            case data
            case sendTo = "send_to"
        }
        
        let data: String
        let sendTo: String
    }
    
    struct ClosedGroupRequestBody: Codable {
        let closedGroupPublicKey: String
        let pubKey: String
    }

    // MARK: - Settings
    public static let server = "https://dev.apns.getsession.org"
    public static let serverPublicKey = "642a6585919742e5a2d4dc51244964fbcd8bcab2b75612407de58b810740d049"
    
    private static let maxRetryCount: UInt = 4
    private static let tokenExpirationInterval: TimeInterval = 12 * 60 * 60

    @objc public enum ClosedGroupOperation : Int {
        case subscribe, unsubscribe
        
        public var endpoint: String {
            switch self {
                case .subscribe: return "subscribe_closed_group"
                case .unsubscribe: return "unsubscribe_closed_group"
            }
        }
    }

    // MARK: - Initialization
    
    private override init() { }

    // MARK: - Registration
    
    public static func unregister(_ token: Data) -> Promise<Void> {
        let requestBody: RegistrationRequestBody = RegistrationRequestBody(token: token.toHexString(), pubKey: nil)
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: HTTP.Error.invalidJSON)
        }
        
        let url = URL(string: "\(server)/unregister")!
        var request: URLRequest = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = [ Header.contentType.rawValue: "application/json" ]
        request.httpBody = body
        
        let promise: Promise<Void> = attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global()) {
            OnionRequestAPI.sendOnionRequest(request, to: server, with: serverPublicKey)
                .map2 { _, data in
                    guard let response: PushServerResponse = try? data?.decoded(as: PushServerResponse.self) else {
                        return SNLog("Couldn't unregister from push notifications.")
                    }
                    guard response.code != 0 else {
                        return SNLog("Couldn't unregister from push notifications due to error: \(response.message ?? "nil").")
                    }
                }
        }
        promise.catch2 { error in
            SNLog("Couldn't unregister from push notifications.")
        }
        
        // Unsubscribe from all closed groups (including ones the user is no longer a member of, just in case)
        Storage.shared.read { db in
            let userPublicKey: String = getUserHexEncodedPublicKey(db)
            
            try ClosedGroup
                .select(.threadId)
                .asRequest(of: String.self)
                .fetchAll(db)
                .forEach { closedGroupPublicKey in
                    performOperation(.unsubscribe, for: closedGroupPublicKey, publicKey: userPublicKey)
                }
        }
        
        return promise
    }

    @objc(unregisterToken:)
    public static func objc_unregister(token: Data) -> AnyPromise {
        return AnyPromise.from(unregister(token))
    }

    public static func register(with token: Data, publicKey: String, isForcedUpdate: Bool) -> Promise<Void> {
        let hexEncodedToken: String = token.toHexString()
        let requestBody: RegistrationRequestBody = RegistrationRequestBody(token: hexEncodedToken, pubKey: publicKey)
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: HTTP.Error.invalidJSON)
        }
        
        let userDefaults = UserDefaults.standard
        let oldToken = userDefaults[.deviceToken]
        let lastUploadTime = userDefaults[.lastDeviceTokenUpload]
        let now = Date().timeIntervalSince1970
        guard isForcedUpdate || hexEncodedToken != oldToken || now - lastUploadTime > tokenExpirationInterval else {
            SNLog("Device token hasn't changed or expired; no need to re-upload.")
            return Promise<Void> { $0.fulfill(()) }
        }
        
        let url = URL(string: "\(server)/register")!
        var request: URLRequest = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = [ Header.contentType.rawValue: "application/json" ]
        request.httpBody = body
        
        var promises: [Promise<Void>] = []
        
        promises.append(
            attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global()) {
                OnionRequestAPI.sendOnionRequest(request, to: server, with: serverPublicKey)
                    .map2 { _, data -> Void in
                        guard let response: PushServerResponse = try? data?.decoded(as: PushServerResponse.self) else {
                            return SNLog("Couldn't register device token.")
                        }
                        guard response.code != 0 else {
                            return SNLog("Couldn't register device token due to error: \(response.message ?? "nil").")
                        }
                        
                        userDefaults[.deviceToken] = hexEncodedToken
                        userDefaults[.lastDeviceTokenUpload] = now
                        userDefaults[.isUsingFullAPNs] = true
                    }
            }
        )
        promises.first?.catch2 { error in
            SNLog("Couldn't register device token.")
        }
        
        // Subscribe to all closed groups
        promises.append(
            contentsOf: Storage.shared
                .read { db -> [String] in
                    try ClosedGroup
                        .select(.threadId)
                        .joining(
                            required: ClosedGroup.members
                                .filter(GroupMember.Columns.profileId == getUserHexEncodedPublicKey(db))
                        )
                        .asRequest(of: String.self)
                        .fetchAll(db)
                }
                .defaulting(to: [])
                .map { closedGroupPublicKey -> Promise<Void> in
                    performOperation(.subscribe, for: closedGroupPublicKey, publicKey: publicKey)
                }
        )
        
        return when(fulfilled: promises)
    }

    @objc(registerWithToken:hexEncodedPublicKey:isForcedUpdate:)
    public static func objc_register(with token: Data, publicKey: String, isForcedUpdate: Bool) -> AnyPromise {
        return AnyPromise.from(register(with: token, publicKey: publicKey, isForcedUpdate: isForcedUpdate))
    }

    @discardableResult
    public static func performOperation(_ operation: ClosedGroupOperation, for closedGroupPublicKey: String, publicKey: String) -> Promise<Void> {
        let isUsingFullAPNs = UserDefaults.standard[.isUsingFullAPNs]
        let requestBody: ClosedGroupRequestBody = ClosedGroupRequestBody(
            closedGroupPublicKey: closedGroupPublicKey,
            pubKey: publicKey
        )
        
        guard isUsingFullAPNs else { return Promise<Void> { $0.fulfill(()) } }
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: HTTP.Error.invalidJSON)
        }
        
        let url = URL(string: "\(server)/\(operation.endpoint)")!
        var request: URLRequest = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = [ Header.contentType.rawValue: "application/json" ]
        request.httpBody = body
        
        let promise: Promise<Void> = attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global()) {
            OnionRequestAPI.sendOnionRequest(request, to: server, with: serverPublicKey)
                .map2 { _, data in
                    guard let response: PushServerResponse = try? data?.decoded(as: PushServerResponse.self) else {
                        return SNLog("Couldn't subscribe/unsubscribe for closed group: \(closedGroupPublicKey).")
                    }
                    guard response.code != 0 else {
                        return SNLog("Couldn't subscribe/unsubscribe for closed group: \(closedGroupPublicKey) due to error: \(response.message ?? "nil").")
                    }
                }
        }
        promise.catch2 { error in
            SNLog("Couldn't subscribe/unsubscribe for closed group: \(closedGroupPublicKey).")
        }
        return promise
    }
    
    @objc(performOperation:forClosedGroupWithPublicKey:userPublicKey:)
    public static func objc_performOperation(_ operation: ClosedGroupOperation, for closedGroupPublicKey: String, publicKey: String) -> AnyPromise {
        return AnyPromise.from(performOperation(operation, for: closedGroupPublicKey, publicKey: publicKey))
    }
    
    // MARK: - Notify
    
    public static func notify(
        recipient: String,
        with message: String,
        maxRetryCount: UInt? = nil,
        queue: DispatchQueue = DispatchQueue.global()
    ) -> Promise<Void> {
        let requestBody: NotifyRequestBody = NotifyRequestBody(data: message, sendTo: recipient)
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: HTTP.Error.invalidJSON)
        }
        
        let url = URL(string: "\(server)/notify")!
        var request: URLRequest = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = [ Header.contentType.rawValue: "application/json" ]
        request.httpBody = body
        
        let retryCount: UInt = (maxRetryCount ?? PushNotificationAPI.maxRetryCount)
        let promise: Promise<Void> = attempt(maxRetryCount: retryCount, recoveringOn: queue) {
            OnionRequestAPI.sendOnionRequest(request, to: server, with: serverPublicKey)
                .map2 { _, data in
                    guard let response: PushServerResponse = try? data?.decoded(as: PushServerResponse.self) else {
                        return SNLog("Couldn't send push notification.")
                    }
                    guard response.code != 0 else {
                        return SNLog("Couldn't send push notification due to error: \(response.message ?? "nil").")
                    }
                }
        }
        
        return promise
    }
}
