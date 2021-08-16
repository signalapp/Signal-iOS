import Foundation
import WebRTC

public enum SignalingMessage {
    case candidate(_ message: RTCIceCandidate)
    case answer(_ message: RTCSessionDescription)
    case offer(_ message: RTCSessionDescription)
    case bye
    
    public static func from(message: String) -> SignalingMessage? {
        guard let data = message.data(using: String.Encoding.utf8),
            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? JSON else { return nil }
        let messageAsJSON: JSON
        if let string = json["msg"] as? String {
            guard let data = string.data(using: String.Encoding.utf8),
                let json = try? JSONSerialization.jsonObject(with: data, options: []) as? JSON else { return nil }
            messageAsJSON = json
        } else {
            messageAsJSON = json
        }
        guard let type = messageAsJSON["type"] as? String else { return nil }
        switch type {
        case "candidate":
            guard let candidate = RTCIceCandidate.candidate(from: messageAsJSON) else { return nil }
            return .candidate(candidate)
        case "answer":
            guard let sdp = messageAsJSON["sdp"] as? String else { return nil }
            return .answer(RTCSessionDescription(type: .answer, sdp: sdp))
        case "offer":
            guard let sdp = messageAsJSON["sdp"] as? String else { return nil }
            return .offer(RTCSessionDescription(type: .offer, sdp: sdp))
        case "bye":
            return .bye
        default: return nil
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
        return try? JSONSerialization.data(withJSONObject: json, options: [ .prettyPrinted ])
    }

    static func candidate(from json: JSON) -> RTCIceCandidate? {
        let sdp = json["candidate"] as? String
        let sdpMid = json["id"] as? String
        let labelStr = json["label"] as? String
        let label = (json["label"] as? Int32) ?? 0
        return RTCIceCandidate(sdp: sdp ?? "", sdpMLineIndex: Int32(labelStr ?? "") ?? label, sdpMid: sdpMid)
    }
}
