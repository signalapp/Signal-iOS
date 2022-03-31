import PromiseKit
import WebRTC
import SessionUIKit
import UIKit
import SessionMessagingKit

extension AppDelegate {

    // MARK: Call handling
    @objc func handleAppActivatedWithOngoingCallIfNeeded() {
        guard let call = AppEnvironment.shared.callManager.currentCall else { return }
        guard MiniCallView.current == nil else { return }
        if let callVC = CurrentAppContext().frontmostViewController() as? CallVC, callVC.call == call { return }
        guard let presentingVC = CurrentAppContext().frontmostViewController() else { preconditionFailure() } // FIXME: Handle more gracefully
        let callVC = CallVC(for: call)
        if let conversationVC = presentingVC as? ConversationVC, let contactThread = conversationVC.thread as? TSContactThread, contactThread.contactSessionID() == call.sessionID {
            callVC.conversationVC = conversationVC
            conversationVC.inputAccessoryView?.isHidden = true
            conversationVC.inputAccessoryView?.alpha = 0
        }
        presentingVC.present(callVC, animated: true, completion: nil)
    }
    
    private func dismissAllCallUI() {
        if let currentBanner = IncomingCallBanner.current { currentBanner.dismiss() }
        if let callVC = CurrentAppContext().frontmostViewController() as? CallVC { callVC.handleEndCallMessage() }
        if let miniCallView = MiniCallView.current { miniCallView.dismiss() }
    }
    
    private func showCallUIForCall(_ call: SessionCall) {
        DispatchQueue.main.async {
            call.reportIncomingCallIfNeeded{ error in
                if let error = error {
                    SNLog("[Calls] Failed to report incoming call to CallKit due to error: \(error)")
                } else {
                    if CurrentAppContext().isMainAppAndActive {
                        guard let presentingVC = CurrentAppContext().frontmostViewController() else { preconditionFailure() } // FIXME: Handle more gracefully
                        if let conversationVC = presentingVC as? ConversationVC, let contactThread = conversationVC.thread as? TSContactThread, contactThread.contactSessionID() == call.sessionID {
                            let callVC = CallVC(for: call)
                            callVC.conversationVC = conversationVC
                            conversationVC.inputAccessoryView?.isHidden = true
                            conversationVC.inputAccessoryView?.alpha = 0
                            presentingVC.present(callVC, animated: true, completion: nil)
                        }
                    }
                }
            }
        }
    }
    
    private func insertCallInfoMessage(for message: CallMessage, using transaction: YapDatabaseReadWriteTransaction) -> TSInfoMessage {
        let thread = TSContactThread.getOrCreateThread(withContactSessionID: message.sender!, transaction: transaction)
        let infoMessage = TSInfoMessage.from(message, associatedWith: thread)
        infoMessage.save(with: transaction)
        return infoMessage
    }
    
    private func showMissedCallTipsIfNeeded(caller: String) {
        let userDefaults = UserDefaults.standard
        guard !userDefaults[.hasSeenCallMissedTips] else { return }
        guard let presentingVC = CurrentAppContext().frontmostViewController() else { preconditionFailure() }
        let callMissedTipsModal = CallMissedTipsModal(caller: caller)
        presentingVC.present(callMissedTipsModal, animated: true, completion: nil)
        userDefaults[.hasSeenCallMissedTips] = true
    }
    
    @objc func setUpCallHandling() {
        // Pre offer messages
        MessageReceiver.handleNewCallOfferMessageIfNeeded = { (message, transaction) in
            guard CurrentAppContext().isMainApp else { return }
            guard let timestamp = message.sentTimestamp, TimestampUtils.isWithinOneMinute(timestamp: timestamp) else {
                // Add missed call message for call offer messages from more than one minute
                let infoMessage = self.insertCallInfoMessage(for: message, using: transaction)
                infoMessage.updateCallInfoMessage(.missed, using: transaction)
                return
            }
            guard SSKPreferences.areCallsEnabled else {
                let infoMessage = self.insertCallInfoMessage(for: message, using: transaction)
                infoMessage.updateCallInfoMessage(.missed, using: transaction)
                let contactName = Storage.shared.getContact(with: message.sender!, using: transaction)?.displayName(for: Contact.Context.regular) ?? message.sender!
                DispatchQueue.main.async {
                    self.showMissedCallTipsIfNeeded(caller: contactName)
                }
                return
            }
            let callManager = AppEnvironment.shared.callManager
            // Ignore pre offer message after the same call instance has been generated
            if let currentCall = callManager.currentCall, currentCall.uuid == message.uuid! { return }
            guard callManager.currentCall == nil else {
                callManager.handleIncomingCallOfferInBusyState(offerMessage: message, using: transaction)
                return
            }
            let infoMessage = self.insertCallInfoMessage(for: message, using: transaction)
            // Handle UI
            if let caller = message.sender, let uuid = message.uuid {
                let call = SessionCall(for: caller, uuid: uuid, mode: .answer)
                call.callMessageID = infoMessage.uniqueId
                self.showCallUIForCall(call)
            }
        }
        // Offer messages
        MessageReceiver.handleOfferCallMessage = { message in
            DispatchQueue.main.async {
                guard let call = AppEnvironment.shared.callManager.currentCall, message.uuid! == call.uuid else { return }
                let sdp = RTCSessionDescription(type: .offer, sdp: message.sdps![0])
                call.didReceiveRemoteSDP(sdp: sdp)
            }
        }
        // Answer messages
        MessageReceiver.handleAnswerCallMessage = { message in
            DispatchQueue.main.async {
                guard let call = AppEnvironment.shared.callManager.currentCall, message.uuid! == call.uuid else { return }
                if message.sender! == getUserHexEncodedPublicKey() {
                    guard !call.hasStartedConnecting else { return }
                    self.dismissAllCallUI()
                    AppEnvironment.shared.callManager.reportCurrentCallEnded(reason: .answeredElsewhere)
                } else {
                    call.invalidateTimeoutTimer()
                    call.hasStartedConnecting = true
                    let sdp = RTCSessionDescription(type: .answer, sdp: message.sdps![0])
                    call.didReceiveRemoteSDP(sdp: sdp)
                    guard let callVC = CurrentAppContext().frontmostViewController() as? CallVC else { return }
                    callVC.handleAnswerMessage(message)
                }
            }
        }
        // End call messages
        MessageReceiver.handleEndCallMessage = { message in
            DispatchQueue.main.async {
                guard let call = AppEnvironment.shared.callManager.currentCall, message.uuid! == call.uuid else { return }
                self.dismissAllCallUI()
                if message.sender! == getUserHexEncodedPublicKey() {
                    AppEnvironment.shared.callManager.reportCurrentCallEnded(reason: .declinedElsewhere)
                } else {
                    AppEnvironment.shared.callManager.reportCurrentCallEnded(reason: .remoteEnded)
                }
            }
        }
    }
    
    // MARK: Configuration message
    @objc(syncConfigurationIfNeeded)
    func syncConfigurationIfNeeded() {
        guard Storage.shared.getUser()?.name != nil else { return }
        let userDefaults = UserDefaults.standard
        let lastSync = userDefaults[.lastConfigurationSync] ?? .distantPast
        guard Date().timeIntervalSince(lastSync) > 7 * 24 * 60 * 60 else { return } // Sync every 2 days
        
        MessageSender.syncConfiguration(forceSyncNow: false)
            .done {
                // Only update the 'lastConfigurationSync' timestamp if we have done the first sync (Don't want
                // a new device config sync to override config syncs from other devices)
                if userDefaults[.hasSyncedInitialConfiguration] {
                    userDefaults[.lastConfigurationSync] = Date()
                }
            }
            .retainUntilComplete()
    }

    // MARK: Closed group poller
    @objc func startClosedGroupPoller() {
        guard OWSIdentityManager.shared().identityKeyPair() != nil else { return }
        ClosedGroupPoller.shared.start()
    }

    @objc func stopClosedGroupPoller() {
        ClosedGroupPoller.shared.stop()
    }

}
