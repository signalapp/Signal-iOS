import CallKit
import SessionUtilitiesKit

extension SessionCallManager {
    public func startCall(_ call: SessionCall, completion: ((Error?) -> Void)?) {
        guard case .offer = call.mode else { return }
        guard !call.hasConnected else { return }
        reportOutgoingCall(call)
        if callController != nil {
            let handle = CXHandle(type: .generic, value: call.sessionID)
            let startCallAction = CXStartCallAction(call: call.callID, handle: handle)
            
            startCallAction.isVideo = false
            
            let transaction = CXTransaction()
            transaction.addAction(startCallAction)
            
            requestTransaction(transaction, completion: completion)
        } else {
            startCallAction()
            completion?(nil)
        }
    }
    
    public func answerCall(_ call: SessionCall, completion: ((Error?) -> Void)?) {
        if callController != nil {
            let answerCallAction = CXAnswerCallAction(call: call.callID)
            let transaction = CXTransaction()
            transaction.addAction(answerCallAction)

            requestTransaction(transaction, completion: completion)
        } else {
            answerCallAction()
            completion?(nil)
        }
    }
    
    public func endCall(_ call: SessionCall, completion: ((Error?) -> Void)?) {
        if callController != nil {
            let endCallAction = CXEndCallAction(call: call.callID)
            let transaction = CXTransaction()
            transaction.addAction(endCallAction)

            requestTransaction(transaction, completion: completion)
        } else {
            endCallAction()
            completion?(nil)
        }
    }
    
    // Not currently in use
    public func setOnHoldStatus(for call: SessionCall) {
        if callController != nil {
            let setHeldCallAction = CXSetHeldCallAction(call: call.callID, onHold: true)
            let transaction = CXTransaction()
            transaction.addAction(setHeldCallAction)

            requestTransaction(transaction)
        }
    }
    
    private func requestTransaction(_ transaction: CXTransaction, completion: ((Error?) -> Void)? = nil) {
        callController?.request(transaction) { error in
            if let error = error {
                SNLog("Error requesting transaction: \(error)")
            } else {
                SNLog("Requested transaction successfully")
            }
            completion?(error)
        }
    }
}
