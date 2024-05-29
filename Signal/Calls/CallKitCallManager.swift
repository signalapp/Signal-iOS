//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CallKit
import LibSignalClient
import SignalServiceKit
import UIKit

/**
 * Requests actions from CallKit
 *
 * @Discussion: Based on SpeakerboxCallManager, from the Apple CallKit
 * example app. Though, its responsibilities are mostly mirrored (and
 * delegated from) CallKitCallUIAdaptee.
 *
 * TODO: Would it simplify things to merge this into CallKitCallUIAdaptee?
 */
final class CallKitCallManager {

    let callController = CXCallController()
    let showNamesOnCallScreen: Bool

    static let kAnonymousCallHandlePrefix = "Signal:"
    static let kGroupCallHandlePrefix = "SignalGroup:"

    private static func decodeGroupId(fromIntentHandle handle: String) -> Data? {
        let prefix = handle.prefix(kGroupCallHandlePrefix.count)
        guard prefix == kGroupCallHandlePrefix else {
            return nil
        }
        do {
            return try Data.data(fromBase64Url: String(handle[prefix.endIndex...]))
        } catch {
            // ignore the error
            return nil
        }
    }

    init(showNamesOnCallScreen: Bool) {
        AssertIsOnMainThread()

        self.showNamesOnCallScreen = showNamesOnCallScreen

        // We cannot assert singleton here, because this class gets rebuilt when the user changes relevant call settings
    }

    func createCallHandleWithSneakyTransaction(for call: SignalCall) -> CXHandle {
        let type: CXHandle.HandleType
        let value: String
        switch call.mode {
        case .individual(let individualCall):
            if !showNamesOnCallScreen {
                let callKitId = CallKitCallManager.kAnonymousCallHandlePrefix + call.localId.uuidString
                CallKitIdStore.setThread(individualCall.thread, forCallKitId: callKitId)
                type = .generic
                value = callKitId
            } else if let phoneNumber = individualCall.remoteAddress.phoneNumber {
                type = .phoneNumber
                value = phoneNumber
            } else {
                type = .generic
                value = individualCall.remoteAddress.serviceIdUppercaseString!
            }
        case .groupThread(let groupThreadCall):
            if !showNamesOnCallScreen {
                let callKitId = CallKitCallManager.kAnonymousCallHandlePrefix + call.localId.uuidString
                CallKitIdStore.setThread(groupThreadCall.groupThread, forCallKitId: callKitId)
                type = .generic
                value = callKitId
            } else {
                type = .generic
                value = Self.kGroupCallHandlePrefix + groupThreadCall.groupThread.groupModel.groupId.asBase64Url
            }
        }
        return CXHandle(type: type, value: value)
    }

    @objc
    static func threadForHandleWithSneakyTransaction(_ handle: String) -> TSThread? {
        owsAssertDebug(!handle.isEmpty)

        let databaseStorage = NSObject.databaseStorage
        let phoneNumberUtil = NSObject.phoneNumberUtil
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        if handle.hasPrefix(kAnonymousCallHandlePrefix) {
            return CallKitIdStore.thread(forCallKitId: handle)
        }

        if let groupId = decodeGroupId(fromIntentHandle: handle) {
            return databaseStorage.read { tx in TSGroupThread.fetch(groupId: groupId, transaction: tx) }
        }

        if let serviceId = try? ServiceId.parseFrom(serviceIdString: handle) {
            return TSContactThread.getOrCreateThread(contactAddress: SignalServiceAddress(serviceId))
        }

        let phoneNumber: String? = {
            guard let localNumber = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber else {
                return nil
            }
            let phoneNumbers = phoneNumberUtil.parsePhoneNumbers(
                userSpecifiedText: handle, localPhoneNumber: localNumber
            )
            return phoneNumbers.first?.toE164()
        }()
        if let phoneNumber {
            return TSContactThread.getOrCreateThread(contactAddress: SignalServiceAddress(phoneNumber: phoneNumber))
        }

        return nil
    }

    // MARK: Actions

    func startCall(_ call: SignalCall) {
        let handle = createCallHandleWithSneakyTransaction(for: call)
        let startCallAction = CXStartCallAction(call: call.localId, handle: handle)

        switch call.mode {
        case .individual(let individualCall):
            startCallAction.isVideo = individualCall.offerMediaType == .video
        case .groupThread(let groupThreadCall):
            // All group calls are video calls even if the local video is off,
            // but what we set here is how the call shows up in the system call log,
            // which controls what happens if the user starts another call from the system call log.
            startCallAction.isVideo = !groupThreadCall.ringRtcCall.isOutgoingVideoMuted
        }

        let transaction = CXTransaction()
        transaction.addAction(startCallAction)

        requestTransaction(transaction)
    }

    func localHangup(call: SignalCall) {
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

    func setIsMuted(call: SignalCall, isMuted: Bool) {
        let muteCallAction = CXSetMutedCallAction(call: call.localId, muted: isMuted)
        let transaction = CXTransaction()
        transaction.addAction(muteCallAction)

        requestTransaction(transaction)
    }

    func answer(call: SignalCall) {
        let answerCallAction = CXAnswerCallAction(call: call.localId)
        let transaction = CXTransaction()
        transaction.addAction(answerCallAction)

        requestTransaction(transaction)
    }

    private func requestTransaction(_ transaction: CXTransaction) {
        callController.request(transaction) { error in
            if let error = error {
                Logger.error("Error requesting transaction: \(error)")
            } else {
                Logger.debug("Requested transaction successfully")
            }
        }
    }

    // MARK: Call Management

    private(set) var calls = [SignalCall]()

    func callWithLocalId(_ localId: UUID) -> SignalCall? {
        guard let index = calls.firstIndex(where: { $0.localId == localId }) else {
            return nil
        }
        return calls[index]
    }

    func addCall(_ call: SignalCall) {
        call.commonState.markReportedToSystem()
        calls.append(call)
    }

    func removeCall(_ call: SignalCall) {
        call.commonState.markRemovedFromSystem()
        guard calls.removeFirst(where: { $0 === call }) != nil else {
            Logger.warn("no call matching: \(call) to remove")
            return
        }
    }

    func removeAllCalls() {
        calls.forEach { $0.commonState.markRemovedFromSystem() }
        calls.removeAll()
    }
}

fileprivate extension Array {

    mutating func removeFirst(where predicate: (Element) throws -> Bool) rethrows -> Element? {
        guard let index = try firstIndex(where: predicate) else {
            return nil
        }

        return remove(at: index)
    }
}
