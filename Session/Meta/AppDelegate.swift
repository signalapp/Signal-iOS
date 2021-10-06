import PromiseKit
import WebRTC
import SessionUIKit
import UIKit

extension AppDelegate {

    @objc
    func setUpCallHandling() {
        // Offer messages
        MessageReceiver.handleOfferCallMessage = { message in
            DispatchQueue.main.async {
                let sdp = RTCSessionDescription(type: .offer, sdp: message.sdps![0])
                guard let presentingVC = CurrentAppContext().frontmostViewController() else { preconditionFailure() } // TODO: Handle more gracefully
                if let conversationVC = presentingVC as? ConversationVC, let contactThread = conversationVC.thread as? TSContactThread, contactThread.contactSessionID() == message.sender! {
                    let callVC = CallVC(for: message.sender!, uuid: message.uuid!, mode: .answer(sdp: sdp))
                    callVC.modalPresentationStyle = .overFullScreen
                    callVC.modalTransitionStyle = .crossDissolve
                    callVC.conversationVC = conversationVC
                    conversationVC.inputAccessoryView?.isHidden = true
                    conversationVC.inputAccessoryView?.alpha = 0
                    presentingVC.present(callVC, animated: true, completion: nil)
                } else {
                    let incomingCallBanner = IncomingCallBanner(for: message.sender!, uuid: message.uuid!, sdp: sdp)
                    incomingCallBanner.show()
                }
            }
        }
        // Answer messages
        MessageReceiver.handleAnswerCallMessage = { message in
            DispatchQueue.main.async {
                if let incomingCallBanner = IncomingCallBanner.current, incomingCallBanner.uuid == message.uuid! { incomingCallBanner.dismiss() }
                if let callVC = CurrentAppContext().frontmostViewController() as? CallVC { callVC.handleAnswerMessage(message) }
                WebRTCSession.current?.dropConnection()
                WebRTCSession.current = nil
            }
        }
        // End call messages
        MessageReceiver.handleEndCallMessage = { message in
            DispatchQueue.main.async {
                if let currentBanner = IncomingCallBanner.current { currentBanner.dismiss() }
                guard let callVC = CurrentAppContext().frontmostViewController() as? CallVC else { return }
                callVC.handleEndCallMessage(message)
            }
        }
    }
    
    @objc(syncConfigurationIfNeeded)
    func syncConfigurationIfNeeded() {
        guard Storage.shared.getUser()?.name != nil else { return }
        let userDefaults = UserDefaults.standard
        let lastSync = userDefaults[.lastConfigurationSync] ?? .distantPast
        guard Date().timeIntervalSince(lastSync) > 7 * 24 * 60 * 60,
            let configurationMessage = ConfigurationMessage.getCurrent() else { return } // Sync every 2 days
        let destination = Message.Destination.contact(publicKey: getUserHexEncodedPublicKey())
        Storage.shared.write { transaction in
            let job = MessageSendJob(message: configurationMessage, destination: destination)
            JobQueue.shared.add(job, using: transaction)
        }
        userDefaults[.lastConfigurationSync] = Date()
    }

    func forceSyncConfigurationNowIfNeeded() -> Promise<Void> {
        guard Storage.shared.getUser()?.name != nil,
            let configurationMessage = ConfigurationMessage.getCurrent() else { return Promise.value(()) }
        let destination = Message.Destination.contact(publicKey: getUserHexEncodedPublicKey())
        let (promise, seal) = Promise<Void>.pending()
        Storage.writeSync { transaction in
            MessageSender.send(configurationMessage, to: destination, using: transaction).done {
                seal.fulfill(())
            }.catch { _ in
                seal.fulfill(()) // Fulfill even if this failed; the configuration in the swarm should be at most 2 days old
            }.retainUntilComplete()
        }
        return promise
    }

    @objc func startClosedGroupPoller() {
        guard OWSIdentityManager.shared().identityKeyPair() != nil else { return }
        ClosedGroupPoller.shared.start()
    }

    @objc func stopClosedGroupPoller() {
        ClosedGroupPoller.shared.stop()
    }
    
    @objc func getAppModeOrSystemDefault() -> AppMode {
        let userDefaults = UserDefaults.standard
        if userDefaults.dictionaryRepresentation().keys.contains("appMode") {
            let mode = userDefaults.integer(forKey: "appMode")
            return AppMode(rawValue: mode) ?? .light
        } else {
            if #available(iOS 13.0, *) {
                return UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
            } else {
                return .light
            }
        }
    }
    
}
