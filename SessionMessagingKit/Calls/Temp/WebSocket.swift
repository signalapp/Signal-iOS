import Foundation
import SocketRocket

public protocol WebSocketDelegate : AnyObject {
    
    func webSocketDidConnect(_ webSocket: WebSocket)
    func webSocketDidDisconnect(_ webSocket: WebSocket)
    func webSocket(_ webSocket: WebSocket, didReceive message: String)
}

public final class WebSocket : NSObject, SRWebSocketDelegate {
    private let socket: SRWebSocket
    public weak var delegate: WebSocketDelegate?
    
    public init(url: URL) {
        socket = SRWebSocket(url: url)
        super.init()
        socket.delegate = self
    }

    public func connect() {
        socket.open()
    }
    
    public func send(_ data: Data) {
        socket.send(data)
    }
    
    public func webSocketDidOpen(_ webSocket: SRWebSocket!) {
         delegate?.webSocketDidConnect(self)
     }
    
    public func webSocket(_ webSocket: SRWebSocket!, didReceiveMessage message: Any!) {
        guard let message = message as? String else { return }
        delegate?.webSocket(self, didReceive: message)
    }
    
    public func disconnect() {
        socket.close()
        delegate?.webSocketDidDisconnect(self)
    }
    
    public func webSocket(_ webSocket: SRWebSocket!, didFailWithError error: Error!) {
        SNLog("Web socket failed with error: \(error?.localizedDescription ?? "nil").")
        disconnect()
    }
    
    public func webSocket(_ webSocket: SRWebSocket!, didCloseWithCode code: Int, reason: String!, wasClean: Bool) {
        SNLog("Web socket closed.")
        disconnect()
    }
}
