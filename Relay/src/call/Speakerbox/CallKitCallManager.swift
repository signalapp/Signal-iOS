//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit
import CallKit
import RelayServiceKit

/**
 * Requests actions from CallKit
 *
 * @Discussion:
 *   Based on SpeakerboxCallManager, from the Apple CallKit Example app. Though, it's responsibilities are mostly 
 *   mirrored (and delegated from) CallKitCallUIAdaptee.
 *   TODO: Would it simplify things to merge this into CallKitCallUIAdaptee?
 */
@available(iOS 10.0, *)
final class CallKitCallManager: NSObject {

    let callController = CXCallController()
    let showNamesOnCallScreen: Bool

//    @objc static let kAnonymousCallHandlePrefix = "Forsta:"
    @objc static let kAnonymousCallHandlePrefix = ""

    required init(showNamesOnCallScreen: Bool) {
        SwiftAssertIsOnMainThread(#function)

        self.showNamesOnCallScreen = showNamesOnCallScreen
        super.init()

        // We cannot assert singleton here, because this class gets rebuilt when the user changes relevant call settings
    }

    // MARK: Actions

    func startCall(_ call: RelayCall) {
        
        let handle = CXHandle(type: .generic, value: call.thread.displayName())
        
//        var handle: CXHandle
//
//        if showNamesOnCallScreen {
//            handle = CXHandle(type: .phoneNumber, value: call.callId)
//        } else {
//            let callKitId = CallKitCallManager.kAnonymousCallHandlePrefix + call.localId.uuidString
//            handle = CXHandle(type: .generic, value: callKitId)
//            OWSPrimaryStorage.shared().setPhoneNumber(call.callId, forCallKitId: callKitId)
//        }

        let startCallAction = CXStartCallAction(call: call.localId, handle: handle)

        startCallAction.isVideo = call.hasLocalVideo

        let transaction = CXTransaction()
        transaction.addAction(startCallAction)

        requestTransaction(transaction)
    }

    func localHangup(call: RelayCall) {
        let endCallAction = CXEndCallAction(call: call.localId)
        let transaction = CXTransaction()
        transaction.addAction(endCallAction)

        requestTransaction(transaction)
    }

    func setHeld(call: RelayCall, onHold: Bool) {
        let setHeldCallAction = CXSetHeldCallAction(call: call.localId, onHold: onHold)
        let transaction = CXTransaction()
        transaction.addAction(setHeldCallAction)

        requestTransaction(transaction)
    }

    func setIsMuted(call: RelayCall, isMuted: Bool) {
        let muteCallAction = CXSetMutedCallAction(call: call.localId, muted: isMuted)
        let transaction = CXTransaction()
        transaction.addAction(muteCallAction)

        requestTransaction(transaction)
    }

    func answer(call: RelayCall) {
        let answerCallAction = CXAnswerCallAction(call: call.localId)
        let transaction = CXTransaction()
        transaction.addAction(answerCallAction)

        requestTransaction(transaction)
    }

    private func requestTransaction(_ transaction: CXTransaction) {
        callController.request(transaction) { error in
            if let error = error {
                Logger.error("\(self.logTag) Error requesting transaction: \(error)")
            } else {
                Logger.debug("\(self.logTag) Requested transaction successfully")
            }
        }
    }

    // MARK: Call Management

    private(set) var calls = [RelayCall]()

    func callWithLocalId(_ localId: UUID) -> RelayCall? {
        guard let index = calls.index(where: { $0.localId == localId }) else {
            return nil
        }
        return calls[index]
    }

    func addCall(_ call: RelayCall) {
        calls.append(call)
    }

    func removeCall(_ call: RelayCall) {
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
