//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ContactsUpdater;
@class OWSBlockingManager;
@class OWSUploadingService;
@class SignalRecipient;
@class TSInvalidIdentityKeySendingErrorMessage;
@class TSNetworkManager;
@class TSOutgoingMessage;
@class TSStorageManager;
@class TSThread;

@protocol ContactsManagerProtocol;

/**
 * Useful for when you *sometimes* want to retry before giving up and calling the failure handler
 * but *sometimes* we don't want to retry when we know it's a terminal failure, so we allow the
 * caller to indicate this with isRetryable=NO.
 */
typedef void (^RetryableFailureHandler)(NSError *_Nonnull error);

// Message send error handling is slightly different for contact and group messages.
//
// For example, If one member of a group deletes their account, the group should
// ignore errors when trying to send messages to this ex-member.
@interface NSError (OWSMessageSender)

- (BOOL)isRetryable;
- (void)setIsRetryable:(BOOL)value;

- (BOOL)shouldBeIgnoredForGroups;
- (void)setShouldBeIgnoredForGroups:(BOOL)value;

@end

#pragma mark -

NS_SWIFT_NAME(MessageSender)
@interface OWSMessageSender : NSObject {

@protected

    // For subclassing in tests
    OWSUploadingService *_uploadingService;
    ContactsUpdater *_contactsUpdater;
}

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager
                        storageManager:(TSStorageManager *)storageManager
                       contactsManager:(id<ContactsManagerProtocol>)contactsManager
                       contactsUpdater:(ContactsUpdater *)contactsUpdater;

- (void)setBlockingManager:(OWSBlockingManager *)blockingManager;

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
            sourceFilename:(nullable NSString *)sourceFilename
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
