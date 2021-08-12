import Foundation
import SocketRocket

public protocol MockWebSocketDelegate : AnyObject {
    
    func webSocketDidConnect(_ webSocket: MockWebSocket)
    func webSocketDidDisconnect(_ webSocket: MockWebSocket)
    func webSocket(_ webSocket: MockWebSocket, didReceive data: String)
}

public final class MockWebSocket : NSObject {
    public weak var delegate: MockWebSocketDelegate?
    private var socket: SRWebSocket?
    
    public var isConnected: Bool {
        return socket != nil
    }
    
    private override init() { }
    
    public static let shared = MockWebSocket()
    
    public func connect(url: URL) {
        socket = SRWebSocket(url: url)
        socket?.delegate = self
        socket?.open()
    }
    
    public func disconnect() {
        socket?.close()
        socket = nil
        delegate?.webSocketDidDisconnect(self)
    }
    
    public func send(_ data: Data) {
        guard let socket = socket else { return }
        socket.send(data)
    }
}

extension MockWebSocket : SRWebSocketDelegate {
    
    public func webSocket(_ webSocket: SRWebSocket!, didReceiveMessage message: Any!) {
        guard let message = message as? String else { return }
        delegate?.webSocket(self, didReceive: message)
    }
    
    public func webSocketDidOpen(_ webSocket: SRWebSocket!) {
        delegate?.webSocketDidConnect(self)
    }
    
    public func webSocket(_ webSocket: SRWebSocket!, didFailWithError error: Error!) {
        SNLog("Web socket failed with error: \(error?.localizedDescription ?? "nil").")
        self.disconnect()
    }
    
    public func webSocket(_ webSocket: SRWebSocket!, didCloseWithCode code: Int, reason: String!, wasClean: Bool) {
        SNLog("Web socket closed.")
        self.disconnect()
    }
}
