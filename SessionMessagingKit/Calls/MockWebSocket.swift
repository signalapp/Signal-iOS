import Foundation
import SocketRocket

protocol MockWebSocketDelegate : AnyObject {
    
    func webSocketDidConnect(_ webSocket: MockWebSocket)
    func webSocketDidDisconnect(_ webSocket: MockWebSocket)
    func webSocket(_ webSocket: MockWebSocket, didReceive data: String)
}

final class MockWebSocket : NSObject {
    weak var delegate: MockWebSocketDelegate?
    var socket: SRWebSocket?
    
    var isConnected: Bool {
        return socket != nil
    }
    
    func connect(url: URL) {
        socket = SRWebSocket(url: url)
        socket?.delegate = self
        socket?.open()
    }
    
    func disconnect() {
        socket?.close()
        socket = nil
        delegate?.webSocketDidDisconnect(self)
    }
    
    func send(data: Data) {
        guard let socket = socket else { return }
        socket.send(data)
    }
}

extension MockWebSocket : SRWebSocketDelegate {
    
    func webSocket(_ webSocket: SRWebSocket!, didReceiveMessage message: Any!) {
        guard let message = message as? String else { return }
        delegate?.webSocket(self, didReceive: message)
    }
    
    func webSocketDidOpen(_ webSocket: SRWebSocket!) {
        delegate?.webSocketDidConnect(self)
    }
    
    func webSocket(_ webSocket: SRWebSocket!, didFailWithError error: Error!) {
        SNLog("Web socket failed with error: \(error?.localizedDescription ?? "nil").")
        self.disconnect()
    }
    
    func webSocket(_ webSocket: SRWebSocket!, didCloseWithCode code: Int, reason: String!, wasClean: Bool) {
        SNLog("Web socket closed.")
        self.disconnect()
    }
}
