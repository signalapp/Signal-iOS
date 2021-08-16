
extension CallVCV2 : WebSocketDelegate {
        
    func webSocketDidConnect(_ webSocket: WebSocket) {
        guard let room = room else { return }
        let json = [
            "cmd" : "register",
            "roomid" : room.roomID,
            "clientid" : room.clientID
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [ .prettyPrinted ]) else { return }
        print("[Calls] Web socket connected. Sending: \(json).")
        webSocket.send(data)
        print("[Calls] Is initiator: \(room.isInitiator).")
        if room.isInitiator {
            callManager.initiateCall().retainUntilComplete()
        }
    }
    
    func webSocketDidDisconnect(_ webSocket: WebSocket) {
        webSocket.delegate = nil
    }
    
    func webSocket(_ webSocket: WebSocket, didReceive message: String) {
        print("[Calls] Message received through web socket: \(message).")
        handle([ message ])
    }
}
