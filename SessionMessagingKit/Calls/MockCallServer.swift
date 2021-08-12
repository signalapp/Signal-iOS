import Foundation
import PromiseKit

public struct RoomInfo {
    public let roomID: String
    public let wssURL: String
    public let wssPostURL: String
    public let clientID: String
    public let isInitiator: String
    public let messages: [String]
}

public enum MockCallServer {
    
    private static func getRoomURL(for roomID: String) -> String {
        let base = MockCallConfig.default.serverURL + "/join/"
        return base + "\(roomID)"
    }
    private static func getLeaveURL(roomID: String, userID: String) -> String {
        let base = MockCallConfig.default.serverURL + "/leave/"
        return base + "\(roomID)/\(userID)"
    }
    private static func getMessageURL(roomID: String, userID: String) -> String {
        let base = MockCallConfig.default.serverURL + "/message/"
        return base + "\(roomID)/\(userID)"
    }
    
    public static func join(roomID: String) -> Promise<RoomInfo> {
        HTTP.execute(.post, getRoomURL(for: roomID)).map2 { json in
            guard let status = json["result"] as? String else { throw HTTP.Error.invalidJSON }
            if status == "FULL" { preconditionFailure() }
            guard let info = json["params"] as? JSON,
                let roomID = info["room_id"] as? String,
                let wssURL = info["wss_url"] as? String,
                let wssPostURL = info["wss_post_url"] as? String,
                let clientID = info["client_id"] as? String,
                let isInitiator = info["is_initiator"] as? String,
                let messages = info["messages"] as? [String] else { throw HTTP.Error.invalidJSON }
            return RoomInfo(roomID: roomID, wssURL: wssURL, wssPostURL: wssPostURL,
                clientID: clientID, isInitiator: isInitiator, messages: messages)
        }
    }
    
    public static func leave(roomID: String, userID: String) -> Promise<Void> {
        return HTTP.execute(.post, getLeaveURL(roomID: roomID, userID: userID)).map2 { _ in }
    }
    
    public static func send(_ message: Data, roomID: String, userID: String) -> Promise<Void> {
        HTTP.execute(.post, getMessageURL(roomID: roomID, userID: userID), body: message).map2 { _ in }
    }
}
