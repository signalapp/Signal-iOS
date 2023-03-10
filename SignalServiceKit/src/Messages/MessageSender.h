//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/DataSource.h>
#import <SignalServiceKit/TSOutgoingMessage.h>

NS_ASSUME_NONNULL_BEGIN

extern const NSUInteger kOversizeTextMessageSizeThreshold;

@class BlockingManager;
@class DeviceMessage;
@class OWSMessageSend;
@class OutgoingMessagePreparer;
@class PendingTasks;
@class SDSAnyWriteTransaction;
@class SignalServiceAddress;
@class TSAttachmentStream;
@class TSOutgoingMessage;
@class TSThread;

@protocol ContactsManagerProtocol;
@protocol UDSendingParamsProvider;

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

#pragma mark -

NS_SWIFT_NAME(OutgoingAttachmentInfo)
@interface OWSOutgoingAttachmentInfo : NSObject

@property (nonatomic, readonly) id<DataSource> dataSource;
@property (nonatomic, readonly) NSString *contentType;
@property (nonatomic, readonly, nullable) NSString *sourceFilename;
@property (nonatomic, readonly, nullable) NSString *caption;
@property (nonatomic, readonly, nullable) NSString *albumMessageId;
@property (nonatomic, readonly) BOOL isBorderless;
@property (nonatomic, readonly) BOOL isLoopingVideo;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithDataSource:(id<DataSource>)dataSource
                       contentType:(NSString *)contentType
                    sourceFilename:(nullable NSString *)sourceFilename
                           caption:(nullable NSString *)caption
                    albumMessageId:(nullable NSString *)albumMessageId
                      isBorderless:(BOOL)isBorderless
                    isLoopingVideo:(BOOL)isLoopingVideo NS_DESIGNATED_INITIALIZER;

- (nullable TSAttachmentStream *)asStreamConsumingDataSourceWithIsVoiceMessage:(BOOL)isVoiceMessage
                                                                         error:(NSError **)error;

@end

#pragma mark -

@interface MessageSender : NSObject

// TODO: Make this private.
@property (nonatomic, readonly) PendingTasks *pendingTasks;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

/**
 * Send and resend text messages or resend messages with existing attachments.
 * If you haven't yet created the attachment, see the `sendAttachment:` variants.
 */
- (void)sendMessage:(OutgoingMessagePreparer *)outgoingMessagePreparer
            success:(void (^)(void))successHandler
            failure:(void (^)(NSError *error))failureHandler;

/**
 * Takes care of allocating and uploading the attachment, then sends the message.
 * Only necessary to call once. If sending fails, retry with `sendMessage:`.
 */
- (void)sendAttachment:(id<DataSource>)dataSource
           contentType:(NSString *)contentType
        sourceFilename:(nullable NSString *)sourceFilename
        albumMessageId:(nullable NSString *)albumMessageId
             inMessage:(TSOutgoingMessage *)outgoingMessage
               success:(void (^)(void))successHandler
               failure:(void (^)(NSError *error))failureHandler;

/**
 * Same as `sendAttachment:`, but deletes the local copy of the attachment after sending.
 * Used for sending sync request data, not for user visible attachments.
 */
- (void)sendTemporaryAttachment:(id<DataSource>)dataSource
                    contentType:(NSString *)contentType
                      inMessage:(TSOutgoingMessage *)outgoingMessage
                        success:(void (^)(void))successHandler
                        failure:(void (^)(NSError *error))failureHandler;

/// Build a ``DeviceMessage`` for the given parameters describing a message.
/// This method may make blocking network requests.
///
/// A `nil` return value with a `nil` error indicates that the given message
/// could not be built due to an invalid device ID.
- (nullable DeviceMessage *)buildDeviceMessageForMessagePlaintextContent:(nullable NSData *)messagePlaintextContent
                                                  messageEncryptionStyle:(EncryptionStyle)messageEncryptionStyle
                                                        recipientAddress:(SignalServiceAddress *)recipientAddress
                                                      recipientAccountId:(NSString *)recipientAccountId
                                                       recipientDeviceId:(NSNumber *)recipientDeviceId
                                                         isOnlineMessage:(BOOL)isOnlineMessage
                                 isTransientSenderKeyDistributionMessage:(BOOL)isTransientSenderKeyDistributionMessage
                                                      isStorySendMessage:(BOOL)isStorySendMessage
                                                  isResendRequestMessage:(BOOL)isResendRequestMessage
                                                 udSendingParamsProvider:
                                                     (nullable id<UDSendingParamsProvider>)udSendingParamsProvider
                                                                   error:(NSError **)errorHandle;
__attribute__((swift_error(nonnull_error)));

+ (NSOperationQueuePriority)queuePriorityForMessage:(TSOutgoingMessage *)message;

// TODO: Make this private.
- (void)sendMessageToRecipient:(OWSMessageSend *)messageSend;

@end

#pragma mark -

@interface OutgoingMessagePreparerHelper : NSObject

+ (BOOL)doesMessageNeedsToBePrepared:(TSOutgoingMessage *)message NS_SWIFT_NAME(doesMessageNeedsToBePrepared(_:));

/// Persists all necessary data to disk before sending, e.g. generate thumbnails
+ (NSArray<NSString *> *)prepareMessageForSending:(TSOutgoingMessage *)message
                                      transaction:(SDSAnyWriteTransaction *)transaction;

/// Writes attachment to disk and applies original filename to message attributes
+ (BOOL)insertAttachments:(NSArray<OWSOutgoingAttachmentInfo *> *)attachmentInfos
               forMessage:(TSOutgoingMessage *)outgoingMessage
              transaction:(SDSAnyWriteTransaction *)transaction
                    error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
