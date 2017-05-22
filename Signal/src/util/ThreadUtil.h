//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@class TSThread;
@class OWSMessageSender;
@class SignalAttachment;
@class TSContactThread;
@class TSStorageManager;
@class OWSContactsManager;
@class OWSBlockingManager;

NS_ASSUME_NONNULL_BEGIN

@class TSUnreadIndicatorInteraction;

@interface ThreadOffersAndIndicators : NSObject

@property (nonatomic, nullable) TSUnreadIndicatorInteraction *unreadIndicator;

@end

#pragma mark -

@interface ThreadUtil : NSObject

+ (void)sendMessageWithText:(NSString *)text
                   inThread:(TSThread *)thread
              messageSender:(OWSMessageSender *)messageSender;

+ (void)sendMessageWithAttachment:(SignalAttachment *)attachment
                         inThread:(TSThread *)thread
                    messageSender:(OWSMessageSender *)messageSender;

// This method will create and/or remove any offers and indicators
// necessary for this thread.
//
// * If hideUnreadMessagesIndicator is YES, there will be no "unread indicator".
// * Otherwise, if fixedUnreadIndicatorTimestamp is non-null, there will be a "unread indicator".
// * Otherwise, there will be a "unread indicator" if there is one unread message.
+ (ThreadOffersAndIndicators *)ensureThreadOffersAndIndicators:(TSThread *)thread
                                                storageManager:(TSStorageManager *)storageManager
                                               contactsManager:(OWSContactsManager *)contactsManager
                                               blockingManager:(OWSBlockingManager *)blockingManager
                                   hideUnreadMessagesIndicator:(BOOL)hideUnreadMessagesIndicator
                                 fixedUnreadIndicatorTimestamp:(NSNumber *_Nullable)fixedUnreadIndicatorTimestamp;

@end

NS_ASSUME_NONNULL_END
