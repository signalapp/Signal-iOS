import PromiseKit

@objc(LKGroupChatAPI)
public final class LokiGroupChatAPI : NSObject {
    internal static let storage = OWSPrimaryStorage.shared()
    
    @objc public static let serverURL = "https://chat.lokinet.org"
    private static let batchCount = 8
    @objc public static let publicChatMessageType = "network.loki.messenger.publicChat"
    @objc public static let publicChatID = 1
    private static let tokenCollection = "LokiGroupChatTokenCollection"
    
    internal static var userDisplayName: String { return SSKEnvironment.shared.contactsManager.displayName(forPhoneIdentifier: userHexEncodedPublicKey) ?? "Anonymous" }
    private static var userKeyPair: ECKeyPair { return OWSIdentityManager.shared().identityKeyPair()! }
    private static var userHexEncodedPublicKey: String { return userKeyPair.hexEncodedPublicKey }
    
    public enum Error : Swift.Error {
        case tokenParsingFailed, tokenDecryptionFailed, messageParsingFailed
    }
    
    private static func getTokenFromServer() -> Promise<String> {
        print("[Loki] Getting group chat auth token.")
        let url = URL(string: "\(serverURL)/loki/v1/get_challenge?pubKey=\(userHexEncodedPublicKey)")!
        let request = TSRequest(url: url)
        return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }.map { rawResponse in
            guard let json = rawResponse as? JSON, let base64EncodedChallenge = json["cipherText64"] as? String, let base64EncodedServerPublicKey = json["serverPubKey64"] as? String,
                let challenge = Data(base64Encoded: base64EncodedChallenge), var serverPublicKey = Data(base64Encoded: base64EncodedServerPublicKey) else {
                throw Error.tokenParsingFailed
            }
            // Discard the "05" prefix if needed
            if (serverPublicKey.count == 33) {
                let hexEncodedServerPublicKey = serverPublicKey.hexadecimalString
                serverPublicKey = Data.data(fromHex: hexEncodedServerPublicKey.substring(from: 2))!
            }
            // The challenge is prefixed by the 16 bit IV
            guard let tokenAsData = try? DiffieHellman.decrypt(challenge, publicKey: serverPublicKey, privateKey: userKeyPair.privateKey),
                let token = String(bytes: tokenAsData, encoding: .utf8), token.count > 0 else {
                throw Error.tokenDecryptionFailed
            }
            return token
        }
    }
    
    internal static func submitToken(_ token: String) -> Promise<String> {
        print("[Loki] Submitting group chat auth token.")
        let url = URL(string: "\(serverURL)/loki/v1/submit_challenge")!
        let parameters = [ "pubKey" : userHexEncodedPublicKey, "token" : token ]
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        return TSNetworkManager.shared().makePromise(request: request).map { _ in token }
    }
    
    internal static func getToken() -> Promise<String> {
        if let token = storage.dbReadConnection.string(forKey: serverURL, inCollection: tokenCollection), token.count > 0 {
            return Promise.value(token)
        } else {
            return getTokenFromServer().then { submitToken($0) }.map { token -> String in
                storage.dbReadWriteConnection.setObject(token, forKey: serverURL, inCollection: tokenCollection)
                return token
            }
        }
    }
    
    public static func getMessages(for group: UInt) -> Promise<[LokiGroupMessage]> {
        print("[Loki] Getting messages for group chat with ID: \(group).")
        let queryParameters = "include_annotations=1&count=-\(batchCount)"
        let url = URL(string: "\(serverURL)/channels/\(group)/messages?\(queryParameters)")!
        let request = TSRequest(url: url)
        return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }.map { rawResponse in
            guard let json = rawResponse as? JSON, let rawMessages = json["data"] as? [JSON] else {
                print("[Loki] Couldn't parse messages for group chat with ID: \(group) from: \(rawResponse).")
                throw Error.messageParsingFailed
            }
            return rawMessages.flatMap { message in
                guard let annotations = message["annotations"] as? [JSON], let annotation = annotations.first, let value = annotation["value"] as? JSON,
                    let serverID = message["id"] as? UInt, let body = message["text"] as? String, let hexEncodedPublicKey = value["source"] as? String, let displayName = value["from"] as? String,
                    let timestamp = value["timestamp"] as? UInt64 else {
                        print("[Loki] Couldn't parse message for group chat with ID: \(group) from: \(message).")
                        return nil
                }
                guard hexEncodedPublicKey != userHexEncodedPublicKey else { return nil }
                return LokiGroupMessage(serverID: serverID, hexEncodedPublicKey: hexEncodedPublicKey, displayName: displayName, body: body, type: publicChatMessageType, timestamp: timestamp)
            }
        }
    }
    
    public static func sendMessage(_ message: LokiGroupMessage, to group: UInt) -> Promise<LokiGroupMessage> {
        return getToken().then { token -> Promise<LokiGroupMessage> in
            print("[Loki] Sending message to group chat with ID: \(group).")
            let url = URL(string: "\(serverURL)/channels/\(group)/messages")!
            let parameters = message.toJSON()
            let request = TSRequest(url: url, method: "POST", parameters: parameters)
            request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
            let displayName = userDisplayName
            return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }.map { rawResponse in
                // ISO8601DateFormatter doesn't support milliseconds before iOS 11
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                guard let json = rawResponse as? JSON, let message = json["data"] as? JSON, let serverID = message["id"] as? UInt, let body = message["text"] as? String,
                    let dateAsString = message["created_at"] as? String, let date = dateFormatter.date(from: dateAsString) else {
                    print("[Loki] Couldn't parse messages for group chat with ID: \(group) from: \(rawResponse).")
                    throw Error.messageParsingFailed
                }
                let timestamp = UInt64(date.timeIntervalSince1970) * 1000
                return LokiGroupMessage(serverID: serverID, hexEncodedPublicKey: userHexEncodedPublicKey, displayName: displayName, body: body, type: publicChatMessageType, timestamp: timestamp)
            }
        }
    }
    
    @objc(getMessagesForGroup:)
    public static func objc_getMessages(for group: UInt) -> AnyPromise {
        return AnyPromise.from(getMessages(for: group))
    }
    
    @objc(sendMessage:toGroup:)
    public static func objc_sendMessage(_ message: LokiGroupMessage, to group: UInt) -> AnyPromise {
        return AnyPromise.from(sendMessage(message, to: group))
    }
}
