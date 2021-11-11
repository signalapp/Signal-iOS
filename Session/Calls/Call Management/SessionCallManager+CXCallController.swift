import CallKit
import SessionUtilitiesKit

extension SessionCallManager {
    public func startCall(_ call: SessionCall, completion: ((Error?) -> Void)?) {
        guard case .offer = call.mode else { return }
        guard !call.hasConnected else { return }
        let handle = CXHandle(type: .generic, value: call.sessionID)
        let startCallAction = CXStartCallAction(call: call.callID, handle: handle)
        
        startCallAction.isVideo = false
        
        let transaction = CXTransaction()
        transaction.addAction(startCallAction)
        
        reportOutgoingCall(call)
        requestTransaction(transaction, completion: completion)
    }
    
    public func answerCall(_ call: SessionCall, completion: ((Error?) -> Void)?) {
        let answerCallAction = CXAnswerCallAction(call: call.callID)
        let transaction = CXTransaction()
        transaction.addAction(answerCallAction)

        requestTransaction(transaction, completion: completion)
    }
    
    public func endCall(_ call: SessionCall, completion: ((Error?) -> Void)?) {
        let endCallAction = CXEndCallAction(call: call.callID)
        let transaction = CXTransaction()
        transaction.addAction(endCallAction)

        requestTransaction(transaction, completion: completion)
    }
    
    // Not currently in use
    public func setOnHoldStatus(for call: SessionCall) {
        let setHeldCallAction = CXSetHeldCallAction(call: call.callID, onHold: true)
        let transaction = CXTransaction()
        transaction.addAction(setHeldCallAction)

        requestTransaction(transaction)
    }
    
    private func requestTransaction(_ transaction: CXTransaction, completion: ((Error?) -> Void)? = nil) {
        callController.request(transaction) { error in
            if let error = error {
                SNLog("Error requesting transaction: \(error)")
            } else {
                SNLog("Requested transaction successfully")
            }
            completion?(error)
        }
    }
}
