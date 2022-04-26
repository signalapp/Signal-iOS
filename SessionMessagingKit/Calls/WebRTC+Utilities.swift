import WebRTC

extension RTCSignalingState : CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .stable: return "stable"
        case .haveLocalOffer: return "haveLocalOffer"
        case .haveLocalPrAnswer: return "haveLocalPrAnswer"
        case .haveRemoteOffer: return "haveRemoteOffer"
        case .haveRemotePrAnswer: return "haveRemotePrAnswer"
        case .closed: return "closed"
        default: preconditionFailure()
        }
    }
}

extension RTCIceConnectionState : CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .new: return "new"
        case .checking: return "checking"
        case .connected: return "connected"
        case .completed: return "completed"
        case .failed: return "failed"
        case .disconnected: return "disconnected"
        case .closed: return "closed"
        case .count: return "count"
        default: preconditionFailure()
        }
    }
}

extension RTCIceGatheringState : CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .new: return "new"
        case .gathering: return "gathering"
        case .complete: return "complete"
        default: preconditionFailure()
        }
    }
}
