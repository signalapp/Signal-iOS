import Foundation
import PromiseKit

public enum TestCallServer {
    
    public enum Error : LocalizedError {
        case roomFull
        
        public var errorDescription: String? {
            switch self {
            case .roomFull: return "The room is full."
            }
        }
    }
    
    public static func join(roomID: String) -> Promise<RoomInfo> {
        let url = "\(TestCallConfig.defaultServerURL)/join/\(roomID)"
        return HTTP.execute(.post, url).map2 { json in
            guard let status = json["result"] as? String else { throw HTTP.Error.invalidJSON }
            guard status != "FULL" else { throw Error.roomFull }
            guard let info = json["params"] as? JSON,
                let roomID = info["room_id"] as? String,
                let wssURL = info["wss_url"] as? String,
                let wssPostURL = info["wss_post_url"] as? String,
                let clientID = info["client_id"] as? String else { throw HTTP.Error.invalidJSON }
            let isInitiator: Bool
            if let bool = info["is_initiator"] as? Bool {
                isInitiator = bool
            } else if let string = info["is_initiator"] as? String {
                isInitiator = (string == "true")
            } else {
                throw HTTP.Error.invalidJSON
            }
            let messages = info["messages"] as? [String]
            return RoomInfo(roomID: roomID, wssURL: wssURL, wssPostURL: wssPostURL,
                clientID: clientID, isInitiator: isInitiator, messages: messages)
        }
    }
    
    public static func leave(roomID: String, userID: String) -> Promise<Void> {
        let url = "\(TestCallConfig.defaultServerURL)/leave/\(roomID)/\(userID)"
        return HTTP.execute(.post, url).map2 { _ in }
    }
    
    public static func send(_ message: Data, roomID: String, userID: String) -> Promise<Void> {
        let url = "\(TestCallConfig.defaultServerURL)/message/\(roomID)/\(userID)"
        return HTTP.execute(.post, url, body: message).map2 { _ in }
    }
}
