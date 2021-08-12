import Foundation
import WebRTC

public enum SignalingMessage {
    case none
    case candidate(_ message: RTCIceCandidate)
    case answer(_ message: RTCSessionDescription)
    case offer(_ message: RTCSessionDescription)
    case bye
    
    public static func from(message: String) -> SignalingMessage {
        guard let data = message.data(using: String.Encoding.utf8) else { return .none }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? JSON else { return .none }
        let messageAsJSON: JSON
        if let foo = json["msg"] as? String {
            guard let data = foo.data(using: String.Encoding.utf8) else { return .none }
            guard let bar = try? JSONSerialization.jsonObject(with: data, options: []) as? JSON else { return .none }
            messageAsJSON = bar
        } else {
            messageAsJSON = json
        }
        guard let type = messageAsJSON["type"] as? String else { return .none }
        switch type {
        case "candidate":
            guard let candidate = RTCIceCandidate.candidate(from: messageAsJSON) else { return .none }
            return .candidate(candidate)
        case "answer":
            guard let sdp = messageAsJSON["sdp"] as? String else { return .none }
            return .answer(RTCSessionDescription(type: .answer, sdp: sdp))
        case "offer":
            guard let sdp = messageAsJSON["sdp"] as? String else { return .none }
            return .offer(RTCSessionDescription(type: .offer, sdp: sdp))
        case "bye":
            return .bye
        default: return .none
        }
    }
}

extension RTCIceCandidate {
    
    public func serialize() -> Data? {
        let json = [
            "type": "candidate",
            "label": "\(sdpMLineIndex)",
            "id": sdpMid,
            "candidate": sdp
        ]
        return try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
    }

    static func candidate(from json: JSON) -> RTCIceCandidate? {
        let sdp = json["candidate"] as? String
        let sdpMid = json["id"] as? String
        let labelStr = json["label"] as? String
        let label = (json["label"] as? Int32) ?? 0
        return RTCIceCandidate(sdp: sdp ?? "", sdpMLineIndex: Int32(labelStr ?? "") ?? label, sdpMid: sdpMid)
    }
}
