// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit
import SessionMessagingKit

public struct SessionApp {
    static let homeViewController: Atomic<HomeVC?> = Atomic(nil)
    
    // MARK: - View Convenience Methods
    
    public static func presentConversation(for threadId: String, action: ConversationViewModel.Action = .none, animated: Bool) {
        let maybeThread: SessionThread? = Storage.shared.write { db in
            try SessionThread.fetchOrCreate(db, id: threadId, variant: .contact)
        }
        
        guard let variant: SessionThread.Variant = maybeThread?.variant else { return }
        
        self.presentConversation(
            for: threadId,
            threadVariant: variant,
            action: action,
            focusInteractionId: nil,
            animated: animated
        )
    }
    
    public static func presentConversation(
        for threadId: String,
        threadVariant: SessionThread.Variant,
        action: ConversationViewModel.Action,
        focusInteractionId: Int64?,
        animated: Bool
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.presentConversation(
                    for: threadId,
                    threadVariant: threadVariant,
                    action: action,
                    focusInteractionId: focusInteractionId,
                    animated: animated
                )
            }
            return
        }
        
        homeViewController.wrappedValue?.show(
            threadId,
            variant: threadVariant,
            with: action,
            focusedInteractionId: focusInteractionId,
            animated: animated
        )
    }

    // MARK: - Functions
    
    public static func resetAppData(onReset: (() -> ())? = nil) {
        // This _should_ be wiped out below.
        Logger.error("")
        DDLog.flushLog()

        Storage.resetAllStorage()
        ProfileManager.resetProfileStorage()
        Attachment.resetAttachmentStorage()
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
