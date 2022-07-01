// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB

extension SessionCallManager {
    @discardableResult
    public func startCallAction() -> Bool {
        guard let call: CurrentCallProtocol = self.currentCall else { return false }
        
        Storage.shared.writeAsync { db in
            call.startSessionCall(db)
        }
        
        return true
    }
    
    @discardableResult
    public func answerCallAction() -> Bool {
        guard let call: SessionCall = (self.currentCall as? SessionCall) else { return false }
        
        if let _ = CurrentAppContext().frontmostViewController() as? CallVC {
            call.answerSessionCall()
        }
        else {
            guard let presentingVC = CurrentAppContext().frontmostViewController() else { return false } // FIXME: Handle more gracefully
            let callVC = CallVC(for: call)
            
            if let conversationVC = presentingVC as? ConversationVC {
                callVC.conversationVC = conversationVC
                conversationVC.inputAccessoryView?.isHidden = true
                conversationVC.inputAccessoryView?.alpha = 0
            }
            
            presentingVC.present(callVC, animated: true) {
                call.answerSessionCall()
            }
        }
        return true
    }
    
    @discardableResult
    public func endCallAction() -> Bool {
        guard let call: SessionCall = (self.currentCall as? SessionCall) else { return false }
        
        call.endSessionCall()
        
        if call.didTimeout {
            reportCurrentCallEnded(reason: .unanswered)
        }
        else {
            reportCurrentCallEnded(reason: nil)
        }
        
        return true
    }
    
    @discardableResult
    public func setMutedCallAction(isMuted: Bool) -> Bool {
        guard let call: SessionCall = (self.currentCall as? SessionCall) else { return false }
        
        call.isMuted = isMuted
        
        return true
    }
}
