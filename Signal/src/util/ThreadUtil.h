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

@interface ThreadUtil : NSObject

+ (void)sendMessageWithText:(NSString *)text
                   inThread:(TSThread *)thread
              messageSender:(OWSMessageSender *)messageSender;

+ (void)sendMessageWithAttachment:(SignalAttachment *)attachment
                         inThread:(TSThread *)thread
                    messageSender:(OWSMessageSender *)messageSender;

+ (void)createBlockOfferIfNecessary:(TSContactThread *)contactThread
                     storageManager:(TSStorageManager *)storageManager
                    contactsManager:(OWSContactsManager *)contactsManager
                    blockingManager:(OWSBlockingManager *)blockingManager;

@end

NS_ASSUME_NONNULL_END
