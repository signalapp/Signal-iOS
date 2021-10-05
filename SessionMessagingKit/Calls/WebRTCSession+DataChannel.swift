import WebRTC
import Foundation

extension WebRTCSession: RTCDataChannelDelegate {
    
    internal func createDataChannel() {
        let dataChannelConfiguration = RTCDataChannelConfiguration()
        dataChannelConfiguration.isOrdered = true
        dataChannelConfiguration.isNegotiated = true
        dataChannelConfiguration.maxRetransmits = 30
        dataChannelConfiguration.maxPacketLifeTime = 30000
        dataChannel = peerConnection.dataChannel(forLabel: "DATACHANNEL", configuration: dataChannelConfiguration)
        dataChannel?.delegate = self
    }
    
    public func sendJSON(_ json: JSON) {
        if let dataChannel = dataChannel, let jsonAsData = try? JSONSerialization.data(withJSONObject: json, options: [ .fragmentsAllowed ]) {
            let dataBuffer = RTCDataBuffer(data: jsonAsData, isBinary: false)
            dataChannel.sendData(dataBuffer)
        }
    }
    
    // MARK: Data channel delegate
    public func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("[Calls] Data channed did change to \(dataChannel.readyState)")
    }
    
    public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        print("[Calls] Data channel did receive data: \(buffer)")
        if let json = try? JSONSerialization.jsonObject(with: buffer.data, options: [ .fragmentsAllowed ]) as? JSON {
            if let isRemoteVideoEnabled = json["video"] as? Bool {
                delegate?.isRemoteVideoDidChange(isEnabled: isRemoteVideoEnabled)
            }
        }
    }
}
