import CallKit
import SessionMessagingKit

public final class SessionCallManager: NSObject {
    let provider: CXProvider
    let callController = CXCallController()
    var currentCall: SessionCall?
    
    private static var _sharedProvider: CXProvider?
    class func sharedProvider(useSystemCallLog: Bool) -> CXProvider {
        let configuration = buildProviderConfiguration(useSystemCallLog: useSystemCallLog)

        if let sharedProvider = self._sharedProvider {
            sharedProvider.configuration = configuration
            return sharedProvider
        } else {
            SwiftSingletons.register(self)
            let provider = CXProvider(configuration: configuration)
            _sharedProvider = provider
            return provider
        }
    }
    
    class func buildProviderConfiguration(useSystemCallLog: Bool) -> CXProviderConfiguration {
        let localizedName = NSLocalizedString("APPLICATION_NAME", comment: "Name of application")
        let providerConfiguration = CXProviderConfiguration(localizedName: localizedName)
        providerConfiguration.supportsVideo = true
        providerConfiguration.maximumCallsPerCallGroup = 1
        providerConfiguration.supportedHandleTypes = [.generic]
        let iconMaskImage = #imageLiteral(resourceName: "SessionGreen32")
        providerConfiguration.iconTemplateImageData = iconMaskImage.pngData()
        providerConfiguration.includesCallsInRecents = useSystemCallLog

        return providerConfiguration
    }
    
    init(useSystemCallLog: Bool = false) {
        AssertIsOnMainThread()
        self.provider = type(of: self).sharedProvider(useSystemCallLog: useSystemCallLog)
        
        super.init()

        // We cannot assert singleton here, because this class gets rebuilt when the user changes relevant call settings
        self.provider.setDelegate(self, queue: nil)
    }
    
    public func reportOutgoingCall(_ call: SessionCall) {
        AssertIsOnMainThread()
        self.currentCall = call
        call.hasStartedConnectingDidChange = {
            self.provider.reportOutgoingCall(with: call.uuid, startedConnectingAt: call.connectingDate)
        }
        call.hasConnectedDidChange = {
            self.provider.reportOutgoingCall(with: call.uuid, connectedAt: call.connectedDate)
        }
    }
    
    public func reportIncomingCall(_ call: SessionCall, callerName: String, completion: @escaping (Error?) -> Void) {
        AssertIsOnMainThread()
        
        // Construct a CXCallUpdate describing the incoming call, including the caller.
        let update = CXCallUpdate()
        update.localizedCallerName = callerName
        update.remoteHandle = CXHandle(type: .generic, value: call.uuid.uuidString)
        update.hasVideo = true

        disableUnsupportedFeatures(callUpdate: update)

        // Report the incoming call to the system
        self.provider.reportNewIncomingCall(with: call.uuid, update: update) { error in
            guard error == nil else {
                completion(error)
                Logger.error("failed to report new incoming call, error: \(error!)")
                return
            }
            self.currentCall = call
            completion(nil)
        }
    }
    
    public func reportCurrentCallEnded(reason: CXCallEndedReason?) {
        guard let call = currentCall else { return }
        if let reason = reason {
            self.provider.reportCall(with: call.uuid, endedAt: nil, reason: reason)
        }
        self.currentCall?.webRTCSession.dropConnection()
        self.currentCall = nil
        WebRTCSession.current = nil
    }
    
    // MARK: Util
    private func disableUnsupportedFeatures(callUpdate: CXCallUpdate) {
        // Call Holding is failing to restart audio when "swapping" calls on the CallKit screen
        // until user returns to in-app call screen.
        callUpdate.supportsHolding = false

        // Not yet supported
        callUpdate.supportsGrouping = false
        callUpdate.supportsUngrouping = false

        // Is there any reason to support this?
        callUpdate.supportsDTMF = false
    }
    
    internal func showCallModal() {
        let callModal = CallModal() { [weak self] in
            self?.showCallVC()
        }
        callModal.modalPresentationStyle = .overFullScreen
        callModal.modalTransitionStyle = .crossDissolve
        guard let presentingVC = CurrentAppContext().frontmostViewController() else { preconditionFailure() } // TODO: Handle more gracefully
        presentingVC.present(callModal, animated: true, completion: nil)
    }
    
    internal func showCallVC() {
        guard let presentingVC = CurrentAppContext().frontmostViewController() else { preconditionFailure() } // TODO: Handle more gracefully
        let callVC = CallVC(for: self.currentCall!)
        callVC.shouldAnswer = true
        if let conversationVC = presentingVC as? ConversationVC {
            callVC.conversationVC = conversationVC
            conversationVC.inputAccessoryView?.isHidden = true
            conversationVC.inputAccessoryView?.alpha = 0
        }
        presentingVC.present(callVC, animated: true, completion: nil)
    }
}

