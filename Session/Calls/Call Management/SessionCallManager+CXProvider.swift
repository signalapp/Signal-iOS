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
        print("[CallKit] Perform CXAnswerCallAction")
        guard let call = self.currentCall else { return action.fail() }
        if CurrentAppContext().isMainAppAndActive {
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
        } else {
            call.answerSessionCallInBackground(action: action)
        }
    }
    
    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        print("[CallKit] Perform CXEndCallAction")
        AssertIsOnMainThread()
        guard let call = self.currentCall else { return action.fail() }
        call.endSessionCall()
        reportCurrentCallEnded(reason: nil)
        action.fulfill()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        print("[CallKit] Perform CXSetMutedCallAction, isMuted: \(action.isMuted)")
        AssertIsOnMainThread()
        guard let call = self.currentCall else { return action.fail() }
        call.isMuted = action.isMuted
        action.fulfill()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        // TODO: set on hold
    }
    
    public func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        // TODO: handle timeout
    }
    
    public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        print("[CallKit] Audio session did activate.")
        AssertIsOnMainThread()
        guard let call = self.currentCall else { return }
        call.webRTCSession.audioSessionDidActivate(audioSession)
    }
    
    public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        print("[CallKit] Audio session did deactivate.")
        AssertIsOnMainThread()
        guard let call = self.currentCall else { return }
        call.webRTCSession.audioSessionDidDeactivate(audioSession)
    }
}

