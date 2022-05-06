// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit
import SessionMessagingKit

public struct SessionApp {
    static let homeViewController: Atomic<HomeVC?> = Atomic(nil)
    
    // MARK: - View Convenience Methods
    
    public static func presentConversation(for recipientId: String, action: ConversationViewModel.Action = .none, animated: Bool) {
        let maybeThread: SessionThread? = GRDBStorage.shared.write { db in
            try SessionThread.fetchOrCreate(db, id: recipientId, variant: .contact)
        }
        
        guard maybeThread != nil else { return }
        
        self.presentConversation(for: recipientId, action: action, animated: animated)
    }
    
    public static func presentConversation(for threadId: String, animated: Bool) {
        guard GRDBStorage.shared.read({ db in try SessionThread.exists(db, id: threadId) }) == true else {
            SNLog("Unable to find thread with id:\(threadId)")
            return
        }
        
        self.presentConversation(for: threadId, animated: animated)
    }
    
    public static func presentConversation(
        for threadId: String,
        action: ConversationViewModel.Action = .none,
        focusInteractionId: Int64? = nil,
        animated: Bool
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.presentConversation(
                    for: threadId,
                    action: action,
                    focusInteractionId: focusInteractionId,
                    animated: animated
                )
            }
            return
        }
        
        homeViewController.wrappedValue?.show(
            threadId,
            with: action,
            highlightedInteractionId: focusInteractionId,
            animated: animated
        )
    }

    // MARK: - Functions
    
    public static func resetAppData(onReset: (() -> ())? = nil) {
        // This _should_ be wiped out below.
        Logger.error("")
        DDLog.flushLog()

        OWSStorage.resetAllStorage()
        OWSUserProfile.resetProfileStorage()
        Environment.shared.preferences.clear()
        AppEnvironment.shared.notificationPresenter.clearAllNotifications()

        onReset?()
        exit(0)
    }
    
    public static func showHomeView() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.showHomeView()
            }
            return
        }
        
        let homeViewController: HomeVC = HomeVC()
        let navController: UINavigationController = UINavigationController(rootViewController: homeViewController)
        (UIApplication.shared.delegate as? AppDelegate)?.window?.rootViewController = navController
    }
}
