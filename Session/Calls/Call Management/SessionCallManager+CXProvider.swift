import CallKit

extension SessionCallManager: CXProviderDelegate {
    public func providerDidReset(_ provider: CXProvider) {
        AssertIsOnMainThread()
        currentCall?.endSessionCall()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        AssertIsOnMainThread()
        guard let call = self.currentCall else { return action.fail() }
        call.startSessionCall()
        action.fulfill()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        AssertIsOnMainThread()
        guard let call = self.currentCall else { return action.fail() }
        if let _ = CurrentAppContext().frontmostViewController() as? CallVC {
            call.answerSessionCall()
        } else {
            let userDefaults = UserDefaults.standard
            if userDefaults[.hasSeenCallIPExposureWarning] {
                showCallVC()
            } else {
                showCallModal()
            }
        }
        action.fulfill()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        AssertIsOnMainThread()
        guard let call = self.currentCall else { return action.fail() }
        call.endSessionCall()
        reportCurrentCallEnded(reason: nil)
        action.fulfill()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        // TODO: set on hold
    }
    
    public func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        // TODO: handle timeout
    }
}

