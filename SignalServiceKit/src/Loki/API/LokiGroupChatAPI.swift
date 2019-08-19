import PromiseKit

public enum LokiGroupChatAPIError: Error {
    case failedToParseMessage
    case failedToParseTimestamp
}

@objc(LKGroupChatAPI)
public final class LokiGroupChatAPI : NSObject {
    internal static let storage = OWSPrimaryStorage.shared()
    internal static let contactsManager = SSKEnvironment.shared.contactsManager
    internal static var userHexEncodedPublicKey: String { return OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey }
    
    @objc public static let serverURL = "https://chat.lokinet.org"
    public static let publicChatMessageType = "network.loki.messenger.publicChat"
    public static let publicChatID = 1
    
    private static let batchCount = 8
    
    public static func getMessages(for groupID: UInt) -> Promise<[LokiGroupMessage]> {
        print("[Loki] Getting messages for group chat with ID: \(groupID)")
        let url = URL(string: "\(serverURL)/channels/\(groupID)/messages?include_annotations=1&count=-\(batchCount)")!
        let request = TSRequest(url: url)
        return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }.map { rawResponse in
            guard let json = rawResponse as? JSON, let rawMessages = json["data"] as? [JSON] else {
                print("[Loki] Failed to parse group messages from: \(rawResponse).")
                return []
            }
            return rawMessages.flatMap { message in
                guard let annotations = message["annotations"] as? [JSON], let annotation = annotations.first, let value = annotation["value"] as? JSON,
                    let serverID = message["id"] as? UInt, let body = message["text"] as? String, let hexEncodedPublicKey = value["source"] as? String, let displayName = value["from"] as? String, let timestamp = value["timestamp"] as? UInt64 else {
                        print("[Loki] Failed to parse message from: \(message).")
                        return nil
                }
                
                guard hexEncodedPublicKey != userHexEncodedPublicKey else { return nil }
                
                return LokiGroupMessage(serverID: serverID, hexEncodedPublicKey: hexEncodedPublicKey, displayName: displayName, body: body, type: publicChatMessageType, timestamp: timestamp)
            }
        }
    }
    
    public static func sendMessage(_ message: LokiGroupMessage, groupID: UInt) -> Promise<LokiGroupMessage> {
        let url = URL(string: "\(serverURL)/channels/\(groupID)/messages")!
        let request = TSRequest(url: url, method: "POST", parameters: message.toJSON())
        request.allHTTPHeaderFields = [ "Authorization": "Bearer loki", "Content-Type": "application/json" ]
        return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }.map { rawResponse in
            guard let json = rawResponse as? JSON, let message = json["data"] as? JSON, let serverID = message["id"] as? UInt, let body = message["text"] as? String, let dateAsString = message["created_at"] as? String else {
                print("[Loki] Failed to parse group messages from: \(rawResponse).")
                throw LokiGroupChatAPIError.failedToParseMessage
            }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZ"
            
            guard let date = formatter.date(from: dateAsString) else {
                print("[Loki] Failed to parse message timestamp from: \(message).")
                throw LokiGroupChatAPIError.failedToParseTimestamp
            }
            
            // Timestmap needs to be in milliseconds
            let timestamp = UInt64(date.timeIntervalSince1970) * 1000
            let displayName = contactsManager.displayName(forPhoneIdentifier: userHexEncodedPublicKey) ?? "Anonymous"
            
            return LokiGroupMessage(serverID: serverID, hexEncodedPublicKey: userHexEncodedPublicKey, displayName: displayName, body: body, type: publicChatMessageType, timestamp: timestamp)
        }
    }
    
    // MARK: Public API (Obj-C)
    @objc(getMessagesForGroupID:)
    public static func objc_getMessages(groupID: UInt) -> AnyPromise {
        let promise = getMessages(for: groupID)
        return AnyPromise.from(promise)
    }
    
    @objc(sendMessage:groupID:)
    public static func objc_sendMessage(message: LokiGroupMessage, groupID: UInt) -> AnyPromise {
        let promise = sendMessage(message, groupID: groupID)
        return AnyPromise.from(promise)
    }
}
