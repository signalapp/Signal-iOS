
extension CallVCV2 : WebSocketDelegate {
        
    func handleWebSocketConnected() {
        guard let room = room else { return }
        let json = [
            "cmd" : "register",
            "roomid" : room.roomID,
            "clientid" : room.clientID
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [ .prettyPrinted ]) else { return }
        print("[Calls] Web socket connected. Sending: \(json).")
        socket?.send(data)
        print("[Calls] Is initiator: \(room.isInitiator).")
        if room.isInitiator {
            callManager.offer().retainUntilComplete()
        }
    }
    
    func handleWebSocketDisconnected() {
        socket?.delegate = nil
    }
    
    func handleWebSocketMessage(_ message: String) {
        print("[Calls] Message received through web socket: \(message).")
        handle([ message ])
    }
}
