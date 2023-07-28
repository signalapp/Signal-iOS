//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "MessageSender.h"
#import "AppContext.h"
#import "AxolotlExceptions.h"
#import "FunctionalUtil.h"
#import "HTTPUtils.h"
#import "NSData+keyVersionByte.h"
#import "OWSBackgroundTask.h"
#import "OWSContact.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSError.h"
#import "OWSIdentityManager.h"
#import "OWSOperation.h"
#import "OWSOutgoingCallMessage.h"
#import "OWSOutgoingGroupCallMessage.h"
#import "OWSOutgoingReactionMessage.h"
#import "OWSOutgoingSenderKeyDistributionMessage.h"
#import "OWSOutgoingSentMessageTranscript.h"
#import "OWSOutgoingSyncMessage.h"
#import "OWSUploadOperation.h"
#import "PreKeyBundle+jsonDict.h"
#import "ProfileManagerProtocol.h"
#import "TSAccountManager.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TSIncomingMessage.h"
#import "TSInfoMessage.h"
#import "TSOutgoingMessage.h"
#import "TSQuotedMessage.h"
#import "TSThread.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/Threading.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *NoSessionForTransientMessageException = @"NoSessionForTransientMessageException";

const NSUInteger kOversizeTextMessageSizeThreshold = 2 * 1024;

#pragma mark -

@implementation OWSOutgoingAttachmentInfo

- (instancetype)initWithDataSource:(id<DataSource>)dataSource
                       contentType:(NSString *)contentType
                    sourceFilename:(nullable NSString *)sourceFilename
                           caption:(nullable NSString *)caption
                    albumMessageId:(nullable NSString *)albumMessageId
                      isBorderless:(BOOL)isBorderless
                    isLoopingVideo:(BOOL)isLoopingVideo
{
    self = [super init];
    if (!self) {
        return self;
    }

    _dataSource = dataSource;
    _contentType = contentType;
    _sourceFilename = sourceFilename;
    _caption = caption;
    _albumMessageId = albumMessageId;
    _isBorderless = isBorderless;
    _isLoopingVideo = isLoopingVideo;

    return self;
}

- (nullable TSAttachmentStream *)asStreamConsumingDataSourceWithIsVoiceMessage:(BOOL)isVoiceMessage
                                                                         error:(NSError **)error
{
    TSAttachmentStream *attachmentStream =
        [[TSAttachmentStream alloc] initWithContentType:self.contentType
                                              byteCount:(UInt32)self.dataSource.dataLength
                                         sourceFilename:self.sourceFilename
                                                caption:self.caption
                                         albumMessageId:self.albumMessageId];

    if (isVoiceMessage) {
        attachmentStream.attachmentType = TSAttachmentTypeVoiceMessage;
    } else if (self.isBorderless) {
        attachmentStream.attachmentType = TSAttachmentTypeBorderless;
    } else if (self.isLoopingVideo || attachmentStream.isAnimated) {
        attachmentStream.attachmentType = TSAttachmentTypeGIF;
    }

    BOOL success = [attachmentStream writeConsumingDataSource:self.dataSource error:error];
    if (*error != nil) {
        OWSFailDebug(@"Error: %@", *error);
        return nil;
    }
    if (!success) {
        OWSFailDebug(@"Unknown error.");
        *error = OWSErrorMakeAssertionError(@"Could not consume data source.");
        return nil;
    }

    return attachmentStream;
}
@end

#pragma mark -

/**
 * OWSSendMessageOperation encapsulates all the work associated with sending a message, e.g. uploading attachments,
 * getting proper keys, and retrying upon failure.
 *
 * Used by `MessageSender` to serialize message sending, ensuring that messages are emitted in the order they
 * were sent.
 */
@interface OWSSendMessageOperation : OWSOperation

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithMessage:(TSOutgoingMessage *)message
                  messageSender:(MessageSender *)messageSender
                    pendingTask:(PendingTask *)pendingTask
                        success:(void (^)(void))aSuccessHandler
                        failure:(void (^)(NSError *error))aFailureHandler NS_DESIGNATED_INITIALIZER;

@end

#pragma mark -

@interface OWSSendMessageOperation ()

@property (nonatomic, readonly) TSOutgoingMessage *message;
@property (nonatomic, readonly) MessageSender *messageSender;
@property (nonatomic, readonly) PendingTask *pendingTask;
@property (nonatomic, readonly) void (^successHandler)(void);
@property (nonatomic, readonly) void (^failureHandler)(NSError *error);

@end

#pragma mark -

@implementation OWSSendMessageOperation

- (instancetype)initWithMessage:(TSOutgoingMessage *)message
                  messageSender:(MessageSender *)messageSender
                    pendingTask:(PendingTask *)pendingTask
                        success:(void (^)(void))successHandler
                        failure:(void (^)(NSError *error))failureHandler
{
    self = [super init];
    if (!self) {
        return self;
    }

    _message = message;
    _messageSender = messageSender;
    _pendingTask = pendingTask;
    _successHandler = successHandler;
    _failureHandler = failureHandler;

    self.queuePriority = [MessageSender queuePriorityForMessage:message];

    return self;
}

#pragma mark - OWSOperation overrides

- (nullable NSError *)checkForPreconditionError
{
    __block NSError *_Nullable error = [super checkForPreconditionError];
    if (error) {
        if (error.isNetworkFailureOrTimeout) {
            OWSLogWarn(@"Precondition failure: %@.", error);
        } else {
            OWSFailDebug(@"Precondition failure: %@.", error);
        }
        return error;
    }

    // Sanity check preconditions
    if (self.message.hasAttachments) {
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            for (TSAttachment *attachment in [self.message allAttachmentsWithTransaction:transaction.unwrapGrdbRead]) {
                if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
                    error = [OWSUnretryableMessageSenderError asNSError];
                    break;
                }

                TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;
                if (!attachmentStream.serverId && attachmentStream.cdnKey.length < 1) {
                    OWSFailDebug(@"Attachment missing upload state.");
                    error = [OWSUnretryableMessageSenderError asNSError];
                    break;
                }
                if (!attachmentStream.isUploaded) {
                    OWSFailDebug(@"Attachment not uploaded.");
                    error = [OWSUnretryableMessageSenderError asNSError];
                    break;
                }
            }
        }];
    }

    return error;
}

- (void)run
{
    [self.messageSender sendMessageToServiceObjC:self.message]
        .doneInBackground(^(id value) { [self reportSuccess]; })
        .catchInBackground(^(NSError *error) { [self reportError:error]; });
}

- (void)didSucceed
{
    if (self.message.messageState != TSOutgoingMessageStateSent) {
        OWSFailDebug(@"Unexpected message status: %@", self.message.statusDescription);
    }

    self.successHandler();

    [self.pendingTask complete];
}

- (void)didFailWithError:(NSError *)error
{
    OWSLogError(@"Failed with error: %@ (isRetryable: %d)", error, error.isRetryable);
    self.failureHandler(error);

    [self.pendingTask complete];
}

@end

#pragma mark -

@interface MessageSender ()

@property (atomic, readonly) NSMutableDictionary<NSString *, NSOperationQueue *> *sendingQueueMap;

@end

#pragma mark -

@implementation MessageSender

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _sendingQueueMap = [NSMutableDictionary new];
    _pendingTasks = [[PendingTasks alloc] initWithLabel:@"Message Sends"];

    OWSSingletonAssert();

    return self;
}

- (NSOperationQueue *)sendingQueueForMessage:(TSOutgoingMessage *)message
{
    OWSAssertDebug(message);
    OWSAssertDebug(message.uniqueThreadId);

    NSString *kDefaultQueueKey = @"kDefaultQueueKey";
    NSString *queueKey = message.uniqueThreadId ?: kDefaultQueueKey;
    OWSAssertDebug(queueKey.length > 0);

    if ([kDefaultQueueKey isEqualToString:queueKey]) {
        // when do we get here?
        OWSLogDebug(@"using default message queue");
    }

    @synchronized(self) {
        NSOperationQueue *sendingQueue = self.sendingQueueMap[queueKey];

        if (!sendingQueue) {
            sendingQueue = [NSOperationQueue new];
            sendingQueue.qualityOfService = NSOperationQualityOfServiceUserInitiated;
            sendingQueue.maxConcurrentOperationCount = 1;
            sendingQueue.name = @"MessageSender-Chat";
            self.sendingQueueMap[queueKey] = sendingQueue;
        }

        return sendingQueue;
    }
}

- (void)sendMessage:(OutgoingMessagePreparer *)outgoingMessagePreparer
            success:(void (^)(void))successHandler
            failure:(void (^)(NSError *error))failureHandler
{
    OWSAssertDebug([outgoingMessagePreparer isKindOfClass:[OutgoingMessagePreparer class]]);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block TSOutgoingMessage *message;
        if (outgoingMessagePreparer.canBePreparedWithoutTransaction) {
            message = [outgoingMessagePreparer prepareMessageWithoutTransaction];
        } else {
            __block NSError *error;
            DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                message = [outgoingMessagePreparer prepareMessageWithTransaction:transaction error:&error];
                if (error != nil) {
                    return;
                }
            });
            if (error != nil) {
                dispatch_async(
                    dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ failureHandler(error); });
                return;
            }
        }

        OWSAssertDebug(message);
        if (message.body.length > 0) {
            OWSAssertDebug(
                [message.body lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= kOversizeTextMessageSizeThreshold);
        }

        OWSLogInfo(@"Sending message: %@, timestamp: %llu.", message.class, message.timestamp);

        BOOL canUseV3 = (message.groupMetaMessage == TSGroupMetaMessageUnspecified
            || message.groupMetaMessage == TSGroupMetaMessageDeliver);

        // We create a PendingTask so we can block on flushing all current message sends.
        PendingTask *pendingTask = [self.pendingTasks buildPendingTaskWithLabel:@"Message Send"];

        OWSSendMessageOperation *sendMessageOperation =
            [[OWSSendMessageOperation alloc] initWithMessage:message
                                               messageSender:self
                                                 pendingTask:pendingTask
                                                     success:successHandler
                                                     failure:failureHandler];

        OWSAssertDebug(outgoingMessagePreparer.savedAttachmentIds != nil);
        for (NSString *attachmentId in outgoingMessagePreparer.savedAttachmentIds) {
            OWSUploadOperation *uploadAttachmentOperation =
                [[OWSUploadOperation alloc] initWithAttachmentId:attachmentId
                                                      messageIds:@[ message.uniqueId ]
                                                        canUseV3:canUseV3];
            [sendMessageOperation addDependency:uploadAttachmentOperation];
            [OWSUploadOperation.uploadQueue addOperation:uploadAttachmentOperation];
        }

        [[self sendingQueueForMessage:message] addOperation:sendMessageOperation];
    });
}

- (void)sendTemporaryAttachment:(id<DataSource>)dataSource
                    contentType:(NSString *)contentType
                      inMessage:(TSOutgoingMessage *)message
                        success:(void (^)(void))successHandler
                        failure:(void (^)(NSError *error))failureHandler
{
    OWSAssertDebug(dataSource);

    void (^successWithDeleteHandler)(void) = ^() {
        successHandler();

        OWSLogDebug(@"Removing successful temporary attachment message with attachment ids: %@", message.attachmentIds);

        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            [message anyRemoveWithTransaction:transaction];
            [message removeTemporaryAttachmentsWithTransaction:transaction];
        });
    };

    void (^failureWithDeleteHandler)(NSError *error) = ^(NSError *error) {
        failureHandler(error);

        OWSLogDebug(@"Removing failed temporary attachment message with attachment ids: %@", message.attachmentIds);

        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            [message anyRemoveWithTransaction:transaction];
            [message removeTemporaryAttachmentsWithTransaction:transaction];
        });
    };

    [self sendAttachment:dataSource
             contentType:contentType
          sourceFilename:nil
          albumMessageId:nil
               inMessage:message
                 success:successWithDeleteHandler
                 failure:failureWithDeleteHandler];
}

- (void)sendAttachment:(id<DataSource>)dataSource
           contentType:(NSString *)contentType
        sourceFilename:(nullable NSString *)sourceFilename
        albumMessageId:(nullable NSString *)albumMessageId
             inMessage:(TSOutgoingMessage *)message
               success:(void (^)(void))success
               failure:(void (^)(NSError *error))failure
{
    OWSAssertDebug(dataSource);

    OWSOutgoingAttachmentInfo *attachmentInfo = [[OWSOutgoingAttachmentInfo alloc] initWithDataSource:dataSource
                                                                                          contentType:contentType
                                                                                       sourceFilename:sourceFilename
                                                                                              caption:nil
                                                                                       albumMessageId:albumMessageId
                                                                                         isBorderless:NO
                                                                                       isLoopingVideo:NO];
    [self sendUnpreparedAttachments:@[
        attachmentInfo,
    ]
                          inMessage:message
                            success:success
                            failure:failure];
}

- (void)sendUnpreparedAttachments:(NSArray<OWSOutgoingAttachmentInfo *> *)attachmentInfos
                        inMessage:(TSOutgoingMessage *)message
                          success:(void (^)(void))success
                          failure:(void (^)(NSError *error))failure
{
    OWSAssertDebug(attachmentInfos.count > 0);
    OutgoingMessagePreparer *outgoingMessagePreparer = [[OutgoingMessagePreparer alloc] init:message
                                                                      unsavedAttachmentInfos:attachmentInfos];
    [self sendMessage:outgoingMessagePreparer success:success failure:failure];
}

+ (NSOperationQueuePriority)queuePriorityForMessage:(TSOutgoingMessage *)message
{
    return message.hasRenderableContent ? NSOperationQueuePriorityNormal : NSOperationQueuePriorityLow;
}

@end

@implementation OutgoingMessagePreparerHelper

#pragma mark -

+ (BOOL)doesMessageNeedsToBePrepared:(TSOutgoingMessage *)message
{
    if (message.allAttachmentIds.count > 0 || message.messageSticker != nil || message.quotedMessage != nil) {
        return YES;
    }
    if (message.hasFailedRecipients) {
        return YES;
    }
    return NO;
}

// NOTE: Any changes to this method should be reflected in doesMessageNeedsToBePrepared.
+ (NSArray<NSString *> *)prepareMessageForSending:(TSOutgoingMessage *)message
                                      transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(message);
    OWSAssertDebug(transaction);

    NSMutableArray<NSString *> *attachmentIds = [NSMutableArray new];

    if (message.attachmentIds) {
        [attachmentIds addObjectsFromArray:message.attachmentIds];
    }

    if (message.quotedMessage.thumbnailAttachmentId) {
        // We need to update the message record here to reflect the new attachments we may create.
        [message anyUpdateOutgoingMessageWithTransaction:transaction
                                                   block:^(TSOutgoingMessage *blockParamMessage) {
                                                       TSAttachmentStream *thumbnail = [blockParamMessage.quotedMessage
                                                           createThumbnailIfNecessaryWithTransaction:transaction];
                                                       if (thumbnail.uniqueId) {
                                                           [attachmentIds addObject:thumbnail.uniqueId];
                                                       }
                                                   }];
    }

    if (message.contactShare.avatarAttachmentId != nil) {
        TSAttachment *attachment = [message.contactShare avatarAttachmentWithTransaction:transaction];
        if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
            [attachmentIds addObject:attachment.uniqueId];
        } else {
            OWSFailDebug(@"unexpected avatarAttachment: %@", attachment);
        }
    }

    if (message.linkPreview.imageAttachmentId != nil) {
        TSAttachmentStream *_Nullable attachment =
            [TSAttachmentStream anyFetchAttachmentStreamWithUniqueId:message.linkPreview.imageAttachmentId
                                                         transaction:transaction];
        if (attachment == nil) {
            OWSFailDebug(@"Missing attachment: %@", attachment);
        } else {
            [attachmentIds addObject:attachment.uniqueId];
        }
    }

    if (message.messageSticker.attachmentId != nil) {
        TSAttachmentStream *_Nullable attachment =
            [TSAttachmentStream anyFetchAttachmentStreamWithUniqueId:message.messageSticker.attachmentId
                                                         transaction:transaction];
        if (attachment == nil) {
            OWSFailDebug(@"Missing attachment: %@", attachment);
        } else {
            [attachmentIds addObject:attachment.uniqueId];
        }
    }

    // When we start a message send, all "failed" recipients should be marked as "sending".
    [message updateAllUnsentRecipientsAsSendingWithTransaction:transaction];

    if (message.messageSticker != nil) {
        // Update "Recent Stickers" list to reflect sends.
        [StickerManager stickerWasSent:message.messageSticker.info transaction:transaction];
    }

    return attachmentIds;
}

+ (BOOL)insertAttachments:(NSArray<OWSOutgoingAttachmentInfo *> *)attachmentInfos
               forMessage:(TSOutgoingMessage *)outgoingMessage
              transaction:(SDSAnyWriteTransaction *)transaction
                    error:(NSError **)error
{
    OWSAssertDebug(attachmentInfos.count > 0);
    OWSAssertDebug(outgoingMessage);

    // Eventually we'll pad all outgoing attachments, but currently just stickers.
    // Currently this method is only used to process "body" attachments, which
    // cannot be sent along with stickers.
    OWSAssertDebug(outgoingMessage.messageSticker == nil);

    NSMutableArray<TSAttachmentStream *> *attachmentStreams = [NSMutableArray new];
    for (OWSOutgoingAttachmentInfo *attachmentInfo in attachmentInfos) {
        TSAttachmentStream *_Nullable attachmentStream =
            [attachmentInfo asStreamConsumingDataSourceWithIsVoiceMessage:outgoingMessage.isVoiceMessage error:error];
        if (*error != nil) {
            return NO;
        }
        if (attachmentStream == nil) {
            OWSFailDebug(@"Unknown error.");
            *error = OWSErrorMakeAssertionError(@"Could not insert attachments.");
            return NO;
        }
        OWSAssert(attachmentStream != nil);
        [attachmentStreams addObject:attachmentStream];
    }

    [outgoingMessage
        anyUpdateOutgoingMessageWithTransaction:transaction
                                          block:^(TSOutgoingMessage *blockParamOutgoingMessage) {
                                              NSMutableArray<NSString *> *attachmentIds =
                                                  [blockParamOutgoingMessage.attachmentIds mutableCopy];
                                              for (TSAttachmentStream *attachmentStream in attachmentStreams) {
                                                  [attachmentIds addObject:attachmentStream.uniqueId];
                                              }
                                              blockParamOutgoingMessage.attachmentIds = [attachmentIds copy];
                                          }];

    for (TSAttachmentStream *attachmentStream in attachmentStreams) {
        [attachmentStream anyInsertWithTransaction:transaction];
    }

    return YES;
}

@end

NS_ASSUME_NONNULL_END
