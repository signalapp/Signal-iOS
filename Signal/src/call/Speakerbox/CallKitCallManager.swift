//  Created by Michael Kirk on 12/13/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

import UIKit
import CallKit

/**
 * Based on SpeakerboxCallManager, from the Apple CallKit Example app. Though, it's responsibilities are mostly mirrored (and delegated from) CallUIAdapter?
 * TODO: Would it simplify things to merge this into CallKitCallUIAdaptee?
 */
@available(iOS 10.0, *)
final class CallKitCallManager: NSObject {

    let callController = CXCallController()

    // MARK: Actions

    func startCall(_ call: SignalCall) {
        let handle = CXHandle(type: .phoneNumber, value: call.remotePhoneNumber)
        let startCallAction = CXStartCallAction(call: call.localId, handle: handle)

        startCallAction.isVideo = call.hasVideo

        let transaction = CXTransaction()
        transaction.addAction(startCallAction)

        requestTransaction(transaction)
    }

    func end(call: SignalCall) {
        let endCallAction = CXEndCallAction(call: call.localId)
        let transaction = CXTransaction()
        transaction.addAction(endCallAction)

        requestTransaction(transaction)
    }

    func setHeld(call: SignalCall, onHold: Bool) {
        let setHeldCallAction = CXSetHeldCallAction(call: call.localId, onHold: onHold)
        let transaction = CXTransaction()
        transaction.addAction(setHeldCallAction)

        requestTransaction(transaction)
    }

    private func requestTransaction(_ transaction: CXTransaction) {
        callController.request(transaction) { error in
            if let error = error {
                print("Error requesting transaction: \(error)")
            } else {
                print("Requested transaction successfully")
            }
        }
    }

    // MARK: Call Management

    private(set) var calls = [SignalCall]()

    func callWithLocalId(_ localId: UUID) -> SignalCall? {
        guard let index = calls.index(where: { $0.localId == localId }) else {
            return nil
        }
        return calls[index]
    }

    func addCall(_ call: SignalCall) {
        calls.append(call)
    }

    func removeCall(_ call: SignalCall) {
        calls.removeFirst(where: { $0 === call })
    }

    func removeAllCalls() {
        calls.removeAll()
    }
}


fileprivate extension Array {

    mutating func removeFirst(where predicate: (Element) throws -> Bool) rethrows {
        guard let index = try index(where: predicate) else {
            return
        }

        remove(at: index)
    }
    
}
