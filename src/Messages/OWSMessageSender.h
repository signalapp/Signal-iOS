//  Created by Michael Kirk on 10/7/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class ContactsUpdater;
@class OWSUploadingService;
@class SignalRecipient;
@class TSInvalidIdentityKeySendingErrorMessage;
@class TSNetworkManager;
@class TSOutgoingMessage;
@class TSStorageManager;
@class TSThread;
@protocol ContactsManagerProtocol;

NS_SWIFT_NAME(MessageSender)
@interface OWSMessageSender : NSObject {

@protected

    // For subclassing in tests
    OWSUploadingService *_uploadingService;
    ContactsUpdater *_contactsUpdater;
}

- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager
                        storageManager:(TSStorageManager *)storageManager
                       contactsManager:(id<ContactsManagerProtocol>)contactsManager
                       contactsUpdater:(ContactsUpdater *)contactsUpdater;

/**
 * Send and resend text messages or resend messages with existing attachments.
 * If you haven't yet created the attachment, see the `sendAttachmentData:` variants.
 */
- (void)sendMessage:(TSOutgoingMessage *)message
            success:(void (^)())successHandler
            failure:(void (^)(NSError *error))failureHandler;

/**
 * Takes care of allocating and uploading the attachment, then sends the message.
 * Only necessary to call once. If sending fails, retry with `sendMessage:`.
 */
- (void)sendAttachmentData:(NSData *)attachmentData
               contentType:(NSString *)contentType
                 inMessage:(TSOutgoingMessage *)outgoingMessage
                   success:(void (^)())successHandler
                   failure:(void (^)(NSError *error))failureHandler;

/**
 * Same as `sendAttachmentData:`, but deletes the local copy of the attachment after sending.
 * Used for sending sync request data, not for user visible attachments.
 */
- (void)sendTemporaryAttachmentData:(NSData *)attachmentData
                        contentType:(NSString *)contentType
                          inMessage:(TSOutgoingMessage *)outgoingMessage
                            success:(void (^)())successHandler
                            failure:(void (^)(NSError *error))failureHandler;

/**
 * Resend a message to a select recipient in a thread when previous sending failed due to key error.
 * e.g. If a key change prevents one recipient from receiving the message, we don't want to resend to the entire group.
 */
- (void)resendMessageFromKeyError:(TSInvalidIdentityKeySendingErrorMessage *)errorMessage
                          success:(void (^)())successHandler
                          failure:(void (^)(NSError *error))failureHandler;

- (void)handleMessageSentRemotely:(TSOutgoingMessage *)message sentAt:(uint64_t)sentAt;

/**
 * Set local configuration to match that of the of `outgoingMessage`'s sender
 *
 * We do this because messages and async message latency make it possible for thread participants disappearing messags
 * configuration to get out of sync.
 */
- (void)becomeConsistentWithDisappearingConfigurationForMessage:(TSOutgoingMessage *)outgoingMessage;

@end

NS_ASSUME_NONNULL_END
