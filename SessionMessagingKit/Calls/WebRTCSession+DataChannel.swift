import WebRTC
import Foundation

extension WebRTCSession: RTCDataChannelDelegate {
    
    internal func createDataChannel() -> RTCDataChannel? {
        let dataChannelConfiguration = RTCDataChannelConfiguration()
        dataChannelConfiguration.isOrdered = true
        dataChannelConfiguration.isNegotiated = true
        dataChannelConfiguration.channelId = 548
        guard let dataChannel = peerConnection.dataChannel(forLabel: "CONTROL", configuration: dataChannelConfiguration) else {
            print("[Calls] Couldn't create data channel.")
            return nil
        }
        return dataChannel
    }
    
    public func sendJSON(_ json: JSON) {
        if let dataChannel = self.dataChannel, let jsonAsData = try? JSONSerialization.data(withJSONObject: json, options: [ .fragmentsAllowed ]) {
            print("[Calls] Send json to data channel")
            let dataBuffer = RTCDataBuffer(data: jsonAsData, isBinary: false)
            dataChannel.sendData(dataBuffer)
        }
    }
    
    // MARK: Data channel delegate
    public func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("[Calls] Data channel did change to \(dataChannel.readyState.rawValue)")
        if dataChannel.readyState == .open {
            delegate?.dataChannelDidOpen()
        }
    }
    
    public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        if let json = try? JSONSerialization.jsonObject(with: buffer.data, options: [ .fragmentsAllowed ]) as? JSON {
            print("[Calls] Data channel did receive data: \(json)")
            if let isRemoteVideoEnabled = json["video"] as? Bool {
                delegate?.isRemoteVideoDidChange(isEnabled: isRemoteVideoEnabled)
            }
            if let _ = json["hangup"] {
                delegate?.didReceiveHangUpSignal()
            }
        }
    }
}
