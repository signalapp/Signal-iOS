import CallKit
import SessionMessagingKit

public final class SessionCallManager: NSObject {
    let provider: CXProvider
    let callController = CXCallController()
    var callTimeOutTimer: Timer? = nil
    var currentCall: SessionCall? = nil {
        willSet {
            if (newValue != nil) {
                DispatchQueue.main.async {
                    UIApplication.shared.isIdleTimerDisabled = true
                }
            } else {
                DispatchQueue.main.async {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            }
        }
    }
    
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
        providerConfiguration.maximumCallGroups = 1
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
    
    // MARK: Report calls
    public func reportOutgoingCall(_ call: SessionCall) {
        AssertIsOnMainThread()
        call.stateDidChange = {
            if call.hasStartedConnecting {
                self.provider.reportOutgoingCall(with: call.callID, startedConnectingAt: call.connectingDate)
            }
            if call.hasConnected {
                self.provider.reportOutgoingCall(with: call.callID, connectedAt: call.connectedDate)
            }
        }
        callTimeOutTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { _ in
            guard let currentCall = self.currentCall else { return }
            currentCall.didTimeout = true
            self.endCall(currentCall) { error in
                self.callTimeOutTimer = nil
            }
        }
    }
    
    public func reportIncomingCall(_ call: SessionCall, callerName: String, completion: @escaping (Error?) -> Void) {
        AssertIsOnMainThread()
        
        // Construct a CXCallUpdate describing the incoming call, including the caller.
        let update = CXCallUpdate()
        update.localizedCallerName = callerName
        update.remoteHandle = CXHandle(type: .generic, value: call.callID.uuidString)
        update.hasVideo = false

        disableUnsupportedFeatures(callUpdate: update)

        // Report the incoming call to the system
        self.provider.reportNewIncomingCall(with: call.callID, update: update) { error in
            guard error == nil else {
                self.currentCall = nil
                completion(error)
                Logger.error("failed to report new incoming call, error: \(error!)")
                return
            }
            completion(nil)
        }
    }
    
    public func reportCurrentCallEnded(reason: CXCallEndedReason?) {
        guard let call = currentCall else { return }
        if let reason = reason {
            self.provider.reportCall(with: call.callID, endedAt: nil, reason: reason)
            switch (reason) {
            case .answeredElsewhere: call.updateCallMessage(mode: .answeredElsewhere)
            case .unanswered: call.updateCallMessage(mode: .unanswered)
            case .declinedElsewhere: call.updateCallMessage(mode: .local)
            default: call.updateCallMessage(mode: .remote)
            }
        } else {
            call.updateCallMessage(mode: .local)
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
    
    public func handleIncomingCallOfferInBusyState(offerMessage: CallMessage, using transaction: YapDatabaseReadWriteTransaction) {
        guard let caller = offerMessage.sender, let thread = TSContactThread.fetch(for: caller, using: transaction) else { return }
        let message = CallMessage()
        message.uuid = offerMessage.uuid
        message.kind = .endCall
        print("[Calls] Sending end call message.")
        MessageSender.sendNonDurably(message, in: thread, using: transaction).retainUntilComplete()
        let infoMessage = TSInfoMessage.from(offerMessage, associatedWith: thread)
        infoMessage.save(with: transaction)
        infoMessage.updateCallInfoMessage(.missed, using: transaction)
    }
    
    public func invalidateTimeoutTimer() {
        callTimeOutTimer?.invalidate()
        callTimeOutTimer = nil
    }
}

