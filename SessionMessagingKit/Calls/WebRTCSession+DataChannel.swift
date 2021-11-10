import WebRTC
import Foundation

extension WebRTCSession: RTCDataChannelDelegate {
    
    internal func createDataChannel() -> RTCDataChannel? {
        let dataChannelConfiguration = RTCDataChannelConfiguration()
        guard let dataChannel = peerConnection.dataChannel(forLabel: "VIDEOCONTROL", configuration: dataChannelConfiguration) else {
            print("[Calls] Couldn't create data channel.")
            return nil
        }
        return dataChannel
    }
    
    public func sendJSON(_ json: JSON) {
        if let dataChannel = remoteDataChannel, let jsonAsData = try? JSONSerialization.data(withJSONObject: json, options: [ .fragmentsAllowed ]) {
            let dataBuffer = RTCDataBuffer(data: jsonAsData, isBinary: false)
            dataChannel.sendData(dataBuffer)
        }
    }
    
    // MARK: Data channel delegate
    public func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("[Calls] Data channel did change to \(dataChannel.readyState)")
    }
    
    public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        print("[Calls] Data channel did receive data: \(buffer)")
        if let json = try? JSONSerialization.jsonObject(with: buffer.data, options: [ .fragmentsAllowed ]) as? JSON {
            if let isRemoteVideoEnabled = json["video"] as? Bool {
                delegate?.isRemoteVideoDidChange(isEnabled: isRemoteVideoEnabled)
            }
            if let _ = json["hangup"] {
                delegate?.didReceiveHangUpSignal()
            }
        }
    }
}
