//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class ThreadModel: NSObject {
    let hasUnreadMessages: Bool
    let lastMessageDate: Date
    let isGroupThread: Bool
    let threadRecord: TSThread
    let unreadCount: UInt
    let contactIdentifier: String?
    let name: String
    let isMuted: Bool
    var isContactThread: Bool {
        return !isGroupThread
    }

    let lastMessageText: String?

//    func attributedSnippet(blockedPhoneNumberSet: Set<String>) {
//        let isBlocked: Bool = {
//            guard let contactIdentifier = self.contactIdentifier else {
//                return false
//            }
//            assert(isContactThread)
//            return blockedPhoneNumberSet.contains(self.contactIdentifier)
//        }()
//            
//        
//            
////            BOOL hasUnreadMessages = thread.hasUnreadMessages;
//        
////            NSMutableAttributedString *snippetText = [NSMutableAttributedString new];
//        var snippetText = NSMutableAttributedString()
//        if isBlocked {
//            // If thread is blocked, don't show a snippet or mute status.
//            let append = NSAttributedString(string: NSLocalizedString("HOME_VIEW_BLOCKED_CONTACT_CONVERSATION",
//                                                                      comment: "A label for conversations with blocked users."),
//                attributes: <#T##[String : Any]?#>)
//            
////            if (isBlocked) {
////                // If thread is blocked, don't show a snippet or mute status.
////                [snippetText
////                    appendAttributedString:[[NSAttributedString alloc]
////                    initWithString:NSLocalizedString(@"HOME_VIEW_BLOCKED_CONTACT_CONVERSATION",
////                    @"A label for conversations with blocked users.")
////                    attributes:@{
////                    NSFontAttributeName : self.snippetFont.ows_mediumWeight,
////                    NSForegroundColorAttributeName : [UIColor ows_blackColor],
////                    }]];
////            } else {
////                if ([thread isMuted]) {
////                    [snippetText appendAttributedString:[[NSAttributedString alloc]
////                        initWithString:@"\ue067  "
////                        attributes:@{
////                        NSFontAttributeName : [UIFont ows_elegantIconsFont:9.f],
////                        NSForegroundColorAttributeName : (hasUnreadMessages
////                        ? [UIColor colorWithWhite:0.1f alpha:1.f]
////                        : [UIColor lightGrayColor]),
////                        }]];
////                }
////                NSString *displayableText = thread.lastMessageText;
////                if (displayableText) {
////                    [snippetText appendAttributedString:[[NSAttributedString alloc]
////                        initWithString:displayableText
////                        attributes:@{
////                        NSFontAttributeName :
////                        (hasUnreadMessages ? self.snippetFont.ows_mediumWeight
////                        : self.snippetFont),
////                        NSForegroundColorAttributeName :
////                        (hasUnreadMessages ? [UIColor ows_blackColor]
////                        : [UIColor lightGrayColor]),
////                        }]];
////                }
////            }
////
////            return snippetText;
//        }
//    }

    init(thread: TSThread, transaction: YapDatabaseReadTransaction) {
        self.threadRecord = thread
        self.lastMessageDate = thread.lastMessageDate()
        self.isGroupThread = thread.isGroupThread()
        self.name = thread.name()
        self.isMuted = thread.isMuted
        self.lastMessageText = thread.lastMessageText(transaction: transaction)

        if let contactThread = thread as? TSContactThread {
            self.contactIdentifier = contactThread.contactIdentifier()
        } else {
            self.contactIdentifier = nil
        }

        self.unreadCount = thread.unreadMessageCount(transaction: transaction)
        self.hasUnreadMessages = unreadCount > 0
    }
}
