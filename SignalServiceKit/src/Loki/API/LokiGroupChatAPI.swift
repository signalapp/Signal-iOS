import PromiseKit

@objc(LKGroupChatAPI)
public final class LokiGroupChatAPI : NSObject {
    internal static let storage = OWSPrimaryStorage.shared()
    
    @objc public static let serverURL = "https://chat.lokinet.org"
    private static let batchCount = 8
    @objc public static let publicChatMessageType = "network.loki.messenger.publicChat"
    @objc public static let publicChatID = 1
    
    internal static var userDisplayName: String {
        return SSKEnvironment.shared.contactsManager.displayName(forPhoneIdentifier: userHexEncodedPublicKey) ?? "Anonymous"
    }
    
    private static var userHexEncodedPublicKey: String {
        return OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
    }
    
    public enum Error : Swift.Error {
        case messageParsingFailed
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
                    let serverID = message["id"] as? UInt, let body = message["text"] as? String, let hexEncodedPublicKey = value["source"] as? String, let displayName = value["from"] as? String, let timestamp = value["timestamp"] as? UInt64 else {
                        print("[Loki] Couldn't parse message for group chat with ID: \(group) from: \(message).")
                        return nil
                }
                return LokiGroupMessage(serverID: serverID, hexEncodedPublicKey: hexEncodedPublicKey, displayName: displayName, body: body, type: publicChatMessageType, timestamp: timestamp)
            }
        }
    }
    
    public static func sendMessage(_ message: LokiGroupMessage, to group: UInt) -> Promise<LokiGroupMessage> {
        print("[Loki] Sending message to group chat with ID: \(group).")
        let url = URL(string: "\(serverURL)/channels/\(group)/messages")!
        let parameters = message.toJSON()
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer loki" ]
        let displayName = userDisplayName
        return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }.map { rawResponse in
            guard let json = rawResponse as? JSON, let message = json["data"] as? JSON, let serverID = message["id"] as? UInt, let body = message["text"] as? String, let dateAsString = message["created_at"] as? String, let date = ISO8601DateFormatter().date(from: dateAsString) else {
                print("[Loki] Couldn't parse messages for group chat with ID: \(group) from: \(rawResponse).")
                throw Error.messageParsingFailed
            }
            let timestamp = UInt64(date.timeIntervalSince1970) * 1000
            return LokiGroupMessage(serverID: serverID, hexEncodedPublicKey: userHexEncodedPublicKey, displayName: displayName, body: body, type: publicChatMessageType, timestamp: timestamp)
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
