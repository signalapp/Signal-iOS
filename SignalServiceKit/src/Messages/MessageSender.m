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
#import "SSKPreKeyStore.h"
#import "SSKSignedPreKeyStore.h"
#import "TSAccountManager.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TSIncomingMessage.h"
#import "TSInfoMessage.h"
#import "TSOutgoingMessage.h"
#import "TSPreKeyManager.h"
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

@interface MessageSender (OWSSendMessageOperation)

- (void)sendMessageToService:(TSOutgoingMessage *)message
                     success:(void (^)(void))successHandler
                     failure:(RetryableFailureHandler)failureHandler;

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
        if (error.isNetworkConnectivityFailure) {
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
    if (AppExpiry.shared.isExpired) {
        OWSLogWarn(@"Unable to send because the application has expired.");
        NSError *error = [AppExpiredError asNSError];
        [self reportError:error];
        return;
    }

    if (TSAccountManager.shared.isDeregistered) {
        OWSLogWarn(@"Unable to send because the application is deregistered.");
        NSError *error = [AppDeregisteredError asNSError];
        [self reportError:error];
        return;
    }

    // If the message has been deleted, abort send.
    __block TSInteraction *_Nullable latestCopy;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        latestCopy = [TSInteraction anyFetchWithUniqueId:self.message.uniqueId transaction:transaction];
    }];
    BOOL messageWasRemotelyDeleted = NO;
    if ([latestCopy isKindOfClass:[TSOutgoingMessage class]]) {
        messageWasRemotelyDeleted = ((TSOutgoingMessage *)latestCopy).wasRemotelyDeleted;
    }

    [BenchManager
        completeEventWithEventId:[NSString stringWithFormat:@"sendMessagePreNetwork-%llu", self.message.timestamp]];

    if ((self.message.shouldBeSaved && latestCopy == nil) || messageWasRemotelyDeleted) {
        OWSLogInfo(@"aborting message send; message deleted.");
        NSError *error = [MessageDeletedBeforeSentError asNSError];
        [self reportError:error];
        return;
    }

    [BenchManager startEventWithTitle:[NSString stringWithFormat:@"Send Message Milestone: Network (%llu)",
                                                self.message.timestamp]
                              eventId:[NSString stringWithFormat:@"sendMessageNetwork-%llu", self.message.timestamp]];

    [self.messageSender sendMessageToService:self.message
        success:^{ [self reportSuccess]; }
        failure:^(NSError *error) { [self reportError:error]; }];
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

+ (NSOperationQueue *)globalSendingQueue
{
    static dispatch_once_t onceToken;
    static NSOperationQueue *operationQueue;

    dispatch_once(&onceToken, ^{
        operationQueue = [NSOperationQueue new];
        operationQueue.qualityOfService = NSOperationQualityOfServiceUserInitiated;
        operationQueue.name = @"MessageSender-Global";
        operationQueue.maxConcurrentOperationCount = 5;
    });
    return operationQueue;
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

        NSOperationQueue *sendingQueue = [self sendingQueueForMessage:message];
        NSOperationQueue *globalSendingQueue = MessageSender.globalSendingQueue;

        // We use two "global" operations and the globalSendingQueue
        // to limit how many message sends are in flight at once globally.
        //
        // One global operation runs _before_ sendMessageOperation and
        // ensures that it will not begin while more than N messages
        // sends are in flight at a time.
        //
        // One global operation runs _after_ sendMessageOperation and
        // ensures that subsequent message sends will block behind the
        // message send which are currently enqueuing.
        NSOperation *globalBeforeOperation = [NSOperation new];
        [sendMessageOperation addDependency:globalBeforeOperation];
        NSOperation *globalAfterOperation = [NSOperation new];
        [globalAfterOperation addDependency:sendMessageOperation];

        @synchronized(self) {
            [globalSendingQueue addOperation:globalBeforeOperation];
            [sendingQueue addOperation:sendMessageOperation];
            [globalSendingQueue addOperation:globalAfterOperation];
        }
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

- (void)sendMessageToService:(TSOutgoingMessage *)message
                     success:(void (^)(void))success
                     failure:(RetryableFailureHandler)failure
{
    OWSAssertDebug(!NSThread.isMainThread);

    if (SSKDebugFlags.messageSendsFail.get) {
        NSError *error = [OWSUnretryableMessageSenderError asNSError];
        failure(error);
        return;
    }

    [MessageSender prepareForSendOf:message
                            success:^(MessageSendInfo *sendInfo) {
                                [self sendMessageToService:message sendInfo:sendInfo success:success failure:failure];
                            }
                            failure:failure];
}

- (AnyPromise *)unlockPreKeyUpdateFailuresPromise
{
    OWSAssertDebug(!NSThread.isMainThread);

    if (![TSPreKeyManager isAppLockedDueToPreKeyUpdateFailures]) {
        return [AnyPromise promiseWithValue:@(1)];
    }

    OWSLogInfo(@"Trying to unlock prekey update.");

    return AnyPromise.withFutureOn(
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(AnyFuture *future) {
            OWSProdError([OWSAnalyticsEvents messageSendErrorFailedDueToPrekeyUpdateFailures]);

            // Retry prekey update every time user tries to send a message while app
            // is disabled due to prekey update failures.
            //
            // Only try to update the signed prekey; updating it is sufficient to
            // re-enable message sending.
            [TSPreKeyManager
                rotateSignedPreKeysWithSuccess:^{
                    OWSLogInfo(@"New prekeys registered with server.");
                    [future resolveWithValue:@(1)];
                }
                failure:^(NSError *error) {
                    OWSLogWarn(@"Failed to update prekeys with the server: %@", error);
                    [future rejectWithError:error];
                }];
        });
}

- (AnyPromise *)sendPromiseForServiceIds:(NSArray<ServiceIdObjC *> *)serviceIds
                                 message:(TSOutgoingMessage *)message
                                  thread:(TSThread *)thread
                      senderCertificates:(nullable SenderCertificates *)senderCertificates
                          sendErrorBlock:(void (^_Nonnull)(ServiceIdObjC *address, NSError *))sendErrorBlock
{
    OWSAssertDebug(!NSThread.isMainThread);
    OWSAssertDebug(serviceIds.count > 0);
    OWSAssertDebug(message);
    OWSAssertDebug(thread);

    // 1. Build the plaintext message content.
    __block NSData *_Nullable plaintext = nil;
    __block NSNumber *_Nullable plaintextPayloadId = nil;
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *writeTx) {
        // Record plaintext
        plaintext = [message buildPlainTextData:thread transaction:writeTx];
        plaintextPayloadId = [MessageSendLogObjC recordPayload:plaintext forMessageBeingSent:message tx:writeTx];
    });
    OWSLogDebug(@"built message: %@ plainTextData.length: %lu", [message class], (unsigned long)plaintext.length);

    // 2. Gather "ud sending access".
    NSMutableDictionary<ServiceIdObjC *, OWSUDSendingAccess *> *sendingAccessMap = [NSMutableDictionary new];
    if (senderCertificates != nil) {
        for (ServiceIdObjC *serviceId in serviceIds) {
            if ([self.tsAccountManager.localUuid isEqual:serviceId.uuidValue]) {
                continue;
            }
            if (message.isStorySend) {
                sendingAccessMap[serviceId] = [self.udManager storySendingAccessFor:serviceId
                                                                 senderCertificates:senderCertificates];
            } else {
                sendingAccessMap[serviceId] = [self.udManager udSendingAccessFor:serviceId
                                                               requireSyncAccess:YES
                                                              senderCertificates:senderCertificates];
            }
        }
    }

    // 3. If we have any participants that support sender key, build a promise for their send.
    SenderKeyStatus *senderKeyStatus = [self senderKeyStatusFor:thread
                                             intendedRecipients:serviceIds
                                                    udAccessMap:sendingAccessMap];

    AnyPromise *_Nullable senderKeyMessagePromise = nil;
    NSArray<ServiceIdObjC *> *senderKeyServiceIds = senderKeyStatus.allSenderKeyParticipants;
    NSArray<ServiceIdObjC *> *fanoutServiceIds = senderKeyStatus.fanoutParticipants;
    if (thread.usesSenderKey && senderKeyServiceIds.count >= 2 && message.canSendWithSenderKey) {
        senderKeyMessagePromise = [self senderKeyMessageSendPromiseWithMessage:message
                                                              plaintextContent:plaintext
                                                                     payloadId:plaintextPayloadId
                                                                        thread:thread
                                                                        status:senderKeyStatus
                                                                   udAccessMap:sendingAccessMap
                                                            senderCertificates:senderCertificates
                                                                sendErrorBlock:sendErrorBlock];

        OWSLogDebug(@"%lu / %lu recipients for message: %llu support sender key.",
            senderKeyServiceIds.count,
            serviceIds.count,
            message.timestamp);
    } else {
        senderKeyServiceIds = @[];
        fanoutServiceIds = serviceIds;
        if (!message.canSendWithSenderKey) {
            OWSLogInfo(
                @"Last sender key send attempt failed for message %llu. Falling back to fanout.", message.timestamp);
        } else {
            OWSLogDebug(@"Sender key not supported for message %llu", message.timestamp);
        }
    }
    OWSAssertDebug((fanoutServiceIds.count + senderKeyServiceIds.count) == serviceIds.count);

    // 4. Build a "OWSMessageSend" for each non-senderKey recipient.
    NSMutableArray<OWSMessageSend *> *messageSends = [NSMutableArray new];
    for (ServiceIdObjC *serviceId in fanoutServiceIds) {
        OWSUDSendingAccess *_Nullable udSendingAccess = sendingAccessMap[serviceId];
        OWSMessageSend *messageSend =
            [[OWSMessageSend alloc] initWithMessage:message
                                   plaintextContent:plaintext
                                 plaintextPayloadId:plaintextPayloadId
                                             thread:thread
                                          serviceId:serviceId
                                    udSendingAccess:udSendingAccess
                                       localAddress:self.tsAccountManager.localAddress
                                     sendErrorBlock:^(NSError *error) { sendErrorBlock(serviceId, error); }];
        [messageSends addObject:messageSend];
    }

    // 5. Before kicking of the per-recipient message sends, try
    // to ensure sessions for all recipient devices in parallel.
    return
        [MessageSender ensureSessionsforMessageSendsObjc:messageSends ignoreErrors:YES].thenInBackground(^(id value) {
            // 6. Perform the per-recipient message sends.
            NSMutableArray<AnyPromise *> *sendPromises = [NSMutableArray array];
            for (OWSMessageSend *messageSend in messageSends) {
                [self sendMessageToRecipient:messageSend];
                [sendPromises addObject:messageSend.asAnyPromise];
            }
            // 7. Add the sender-key promise
            if (senderKeyMessagePromise != nil) {
                [sendPromises addObject:senderKeyMessagePromise];
            }

            // We use resolved, not fulfilled, because we don't want the
            // completion promise to execute until _all_ send promises
            // have either succeeded or failed. Fulfilled executes as
            // soon as any of its input promises fail.
            return [AnyPromise whenResolved:sendPromises];
        });
}

- (void)sendMessageToService:(TSOutgoingMessage *)message
                    sendInfo:(MessageSendInfo *)sendInfo
                     success:(void (^)(void))successHandlerParam
                     failure:(RetryableFailureHandler)failureHandlerParam
{
    OWSAssertDebug(!NSThread.isMainThread);

    void (^successHandler)(void) = ^() {
        [self handleMessageSentLocally:message
            success:^{ successHandlerParam(); }
            failure:^(NSError *error) {
                OWSLogError(
                    @"Error sending sync message for message: %@ timestamp: %llu", message.class, message.timestamp);

                failureHandlerParam(error);
            }];
    };
    void (^failureHandler)(NSError *) = ^(NSError *error) {
        if (message.wasSentToAnyRecipient) {
            [self handleMessageSentLocally:message
                success:^{ failureHandlerParam(error); }
                failure:^(NSError *syncError) {
                    OWSLogError(@"Error sending sync message for message: %@ timestamp: %llu, %@",
                        message.class,
                        message.timestamp,
                        syncError);

                    // Discard the "sync message" error in favor of the
                    // original error.
                    failureHandlerParam(error);
                }];
            return;
        }
        failureHandlerParam(error);
    };

    TSThread *thread = sendInfo.thread;
    NSArray<ServiceIdObjC *> *recipientServiceIds = sendInfo.serviceIds;
    SenderCertificates *senderCertificates = sendInfo.senderCertificates;

    BOOL canSendToThread = NO;
    if ([message isKindOfClass:OWSOutgoingReactionMessage.class]) {
        canSendToThread = thread.canSendReactionToThread;
    } else if (message.hasRenderableContent ||
               [message isKindOfClass:OWSOutgoingGroupCallMessage.class] ||
               [message isKindOfClass:OWSOutgoingCallMessage.class]) {
        canSendToThread = [thread canSendChatMessagesToThread];
    } else {
        canSendToThread = thread.canSendNonChatMessagesToThread;
    }

    if (!canSendToThread) {
        if (message.shouldBeSaved) {
            return failureHandler(OWSErrorMakeAssertionError(@"Sending to thread blocked."));
        } else {
            // Pretend to succeed for non-visible messages like read receipts, etc.
            successHandler();
            return;
        }
    }

    if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        // In the "self-send" aka "Note to Self" special case, we only need to send certain kinds of messages.
        // (In particular, regular data messages are sent via their implicit sync message only.)
        if (contactThread.contactAddress.isLocalAddress && !message.canSendToLocalAddress) {
            // Send to self.
            OWSAssertDebug(recipientServiceIds.count == 1);
            OWSLogInfo(@"dropping %@ sent to local address (expected to be sent by sync message)", [message class]);
            // Don't mark self-sent messages as read (or sent) until the sync transcript is sent.
            successHandler();
            return;
        }
    }

    if (recipientServiceIds.count < 1) {
        // All recipients are already sent or can be skipped.
        // NOTE: We might still need to send a sync transcript.
        successHandler();
        return;
    }

    BOOL isNonContactThread = thread.isNonContactThread;
    NSMutableArray<NSError *> *sendErrors = [NSMutableArray array];
    NSMutableDictionary<ServiceIdObjC *, NSError *> *sendErrorPerRecipient = [NSMutableDictionary dictionary];

    [self unlockPreKeyUpdateFailuresPromise]
        .thenInBackground(^(id value) {
            return [self sendPromiseForServiceIds:recipientServiceIds
                                          message:message
                                           thread:thread
                               senderCertificates:senderCertificates
                                   sendErrorBlock:^(ServiceIdObjC *serviceId, NSError *error) {
                                       @synchronized(sendErrors) {
                                           [sendErrors addObject:error];
                                           sendErrorPerRecipient[serviceId] = error;
                                       }
                                   }];
        })
        .doneInBackground(^(id value) { successHandler(); })
        .catchInBackground(^(id failure) {
            // Ignore the failure value; consult sendErrors and sendErrorPerRecipientCopy.
            NSError *firstRetryableError = nil;
            NSError *firstNonRetryableError = nil;

            NSArray<NSError *> *sendErrorsCopy;
            NSDictionary<ServiceIdObjC *, NSError *> *sendErrorPerRecipientCopy;
            @synchronized(sendErrors) {
                sendErrorsCopy = [sendErrors copy];
                sendErrorPerRecipientCopy = [sendErrorPerRecipient copy];
            }

            // Record the individual error for each "failed" recipient.
            DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                for (ServiceIdObjC *serviceId in sendErrorPerRecipientCopy) {
                    NSError *error = sendErrorPerRecipientCopy[serviceId];

                    // Some errors should be ignored when sending messages
                    // to threads other than TSContactThread.  See discussion on
                    // NSError (MessageSender) category.
                    if (isNonContactThread && [error shouldBeIgnoredForNonContactThreads]) {
                        continue;
                    }

                    SignalServiceAddress *address = [[SignalServiceAddress alloc] initWithServiceIdObjC:serviceId];
                    [message updateWithFailedRecipient:address error:error transaction:transaction];
                }
            });

            for (NSError *error in sendErrorsCopy) {
                // Some errors should be ignored when sending messages
                // to threads other than TSContactThread.  See discussion on
                // NSError (MessageSender) category.
                if (isNonContactThread && [error shouldBeIgnoredForNonContactThreads]) {
                    continue;
                }

                // Some errors should never be retried, in order to avoid
                // hitting rate limits, for example.  Unfortunately, since
                // group send retry is all-or-nothing, we need to fail
                // immediately even if some of the other recipients had
                // retryable errors.
                if ([error isFatalError]) {
                    failureHandler(error);
                    return;
                }

                if ([error isRetryable] && !firstRetryableError) {
                    firstRetryableError = error;
                } else if (![error isRetryable] && !firstNonRetryableError) {
                    firstNonRetryableError = error;
                }
            }

            // If any of the send errors are retryable, we want to retry.
            // Therefore, prefer to propagate a retryable error.
            if (firstRetryableError) {
                return failureHandler(firstRetryableError);
            } else if (firstNonRetryableError) {
                return failureHandler(firstNonRetryableError);
            } else {
                // If we only received errors that we should ignore,
                // consider this send a success, unless the message could
                // not be sent to any recipient.
                if (message.sentRecipientsCount == 0) {
                    NSError *error = [MessageSenderErrorNoValidRecipients asNSError];
                    failureHandler(error);
                } else {
                    successHandler();
                }
            }
        });
}

- (void)sendMessageToRecipient:(OWSMessageSend *)messageSend
{
    // [sendMessageToRecipient:] prepares a per-recipient
    // message send and makes the request. It is expensive
    // because encryption is expensive.  Therefore we want
    // to globally limit the number of invocations of this
    // method that are in flight at a time. We use an
    // operation queue to do that.

    static dispatch_once_t onceToken;
    static NSOperationQueue *operationQueue;
    dispatch_once(&onceToken, ^{
        operationQueue = [NSOperationQueue new];
        operationQueue.qualityOfService = NSOperationQualityOfServiceUserInitiated;
        operationQueue.name = @"MessageSender-Recipient";
        operationQueue.maxConcurrentOperationCount = 6;
    });
    [operationQueue addOperationWithBlock:^{ [self _sendMessageToRecipient:messageSend]; }];
}

- (void)_sendMessageToRecipient:(OWSMessageSend *)messageSend
{
    OWSAssertDebug(!NSThread.isMainThread);
    OWSAssertDebug(messageSend);
    OWSAssertDebug(messageSend.thread);

    TSOutgoingMessage *message = messageSend.message;
    ServiceIdObjC *serviceId = messageSend.serviceId;

    OWSLogInfo(
        @"attempting to send message: %@, timestamp: %llu, recipient: %@", message.class, message.timestamp, serviceId);

    if (messageSend.remainingAttempts <= 0) {
        // We should always fail with a specific error.
        OWSProdFail([OWSAnalyticsEvents messageSenderErrorGenericSendFailure]);

        NSError *error = [OWSRetryableMessageSenderError asNSError];
        return messageSend.failure(error);
    }

    // Consume an attempt.
    messageSend.remainingAttempts = messageSend.remainingAttempts - 1;

    // We need to disable UD for sync messages before we build the device messages,
    // since we don't want to build a device message for the local device in the
    // non-UD auth case.
    if (message.isSyncMessage && ![message isKindOfClass:[OWSOutgoingSentMessageTranscript class]]) {
        [messageSend disableUDAuth];
    } else if (SSKDebugFlags.disableUD.value) {
        OWSLogDebug(@"Disabling UD because of testable flag");
        [messageSend disableUDAuth];
    }

    NSError *deviceMessagesError;
    NSArray<DeviceMessage *> *_Nullable deviceMessages = [self buildDeviceMessagesWithMessageSend:messageSend
                                                                                            error:&deviceMessagesError];
    if (deviceMessagesError || !deviceMessages) {
        OWSAssertDebug(deviceMessagesError);
        return messageSend.failure(deviceMessagesError);
    }

    if (messageSend.isLocalAddress) {
        OWSAssertDebug(message.canSendToLocalAddress);
        // We can skip sending sync messages if we know that we have no linked
        // devices. However, we need to be sure to handle the case where the
        // linked device list has just changed.
        //
        // The linked device list is reflected in two separate pieces of state:
        //
        // * OWSDevice's state is updated when you link or unlink a device.
        // * SignalRecipient's state is updated by 409 "Mismatched devices"
        //   responses from the service.
        //
        // If _both_ of these pieces of state agree that there are no linked
        // devices, then can safely skip sending sync message.
        //
        // NOTE: Sync messages sent via UD include the local device.

        __block BOOL mayHaveLinkedDevices;
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            mayHaveLinkedDevices = [OWSDeviceManagerObjcBridge mayHaveLinkedDevicesWithTransaction:transaction];
        }];

        BOOL hasDeviceMessages = NO;
        for (DeviceMessage *deviceMessage in deviceMessages) {
            if (deviceMessage.destinationDeviceId != self.tsAccountManager.storedDeviceId) {
                hasDeviceMessages = YES;
                break;
            }
        }

        OWSLogInfo(@"mayHaveLinkedDevices: %d, hasDeviceMessages: %d", mayHaveLinkedDevices, hasDeviceMessages);

        if (!mayHaveLinkedDevices && !hasDeviceMessages) {
            OWSLogInfo(@"Ignoring sync message without secondary devices: %@", [message class]);

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                // This emulates the completion logic of an actual successful send (see below).
                DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                    [message updateWithSkippedRecipient:messageSend.localAddress transaction:transaction];
                });
                messageSend.success();
            });

            return;
        } else if (mayHaveLinkedDevices && !hasDeviceMessages) {
            // We may have just linked a new secondary device which is not yet reflected in
            // the SignalRecipient that corresponds to ourself.  Proceed.  Client should learn
            // of new secondary devices via 409 "Mismatched devices" response.
            OWSLogWarn(@"account has secondary devices, but sync message has no device messages");
        } else if (!mayHaveLinkedDevices && hasDeviceMessages) {
            OWSFailDebug(@"sync message has device messages for unknown secondary devices.");
        }
    } else {
        // This can happen for users who have unregistered.
        // We still want to try sending to them in case they have re-registered.
        if (deviceMessages.count < 1) {
            OWSLogWarn(@"Message send attempt with no device messages.");
        }
    }

    for (DeviceMessage *deviceMessage in deviceMessages) {
        SSKProtoEnvelopeType messageType = deviceMessage.type;
        BOOL hasValidMessageType = NO;
        if (messageSend.isUDSend) {
            hasValidMessageType |= (messageType == SSKProtoEnvelopeTypeUnidentifiedSender);
        } else {
            hasValidMessageType |= (messageType == SSKProtoEnvelopeTypeCiphertext);
            hasValidMessageType |= (messageType == SSKProtoEnvelopeTypePrekeyBundle);
            hasValidMessageType |= (messageType == SSKProtoEnvelopeTypePlaintextContent);
        }

        if (!hasValidMessageType) {
            OWSFailDebug(@"Invalid message type: %ld", (long)messageType);
            NSError *error = [OWSUnretryableMessageSenderError asNSError];
            return messageSend.failure(error);
        }
    }

    [self performMessageSendRequest:messageSend deviceMessages:deviceMessages];
}

- (void)handleMessageSentLocally:(TSOutgoingMessage *)message
                         success:(void (^)(void))successParam
                         failure:(RetryableFailureHandler)failure
{
    OWSAssertDebug(!NSThread.isMainThread);

    dispatch_block_t success = ^{
        // This should not be nil, even for legacy queued messages.
        __block TSThread *thread;
        [self.databaseStorage
            readWithBlock:^(SDSAnyReadTransaction *tx) { thread = [message threadWithTransaction:tx]; }];
        OWSAssertDebug(thread != nil);

        TSContactThread *_Nullable contactThread;
        if ([thread isKindOfClass:[TSContactThread class]]) {
            contactThread = (TSContactThread *)thread;
        }

        if (contactThread && contactThread.contactAddress.isLocalAddress && !message.isSyncMessage) {
            OWSAssertDebug(message.recipientAddresses.count == 1);
            // Don't mark self-sent messages as read (or sent) until the sync transcript is sent.
            //
            // NOTE: This only applies to the 'note to self' conversation.
            DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                for (SignalServiceAddress *sendingAddress in message.sendingRecipientAddresses) {
                    [message updateWithReadRecipient:sendingAddress
                                   recipientDeviceId:self.tsAccountManager.storedDeviceId
                                       readTimestamp:message.timestamp
                                         transaction:transaction];
                    if (message.isVoiceMessage || message.isViewOnceMessage) {
                        [message updateWithViewedRecipient:sendingAddress
                                         recipientDeviceId:self.tsAccountManager.storedDeviceId
                                           viewedTimestamp:message.timestamp
                                               transaction:transaction];
                    }
                }
            });
        }

        successParam();
    };

    if (message.shouldBeSaved) {
        // We don't need to do this work for transient messages.
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            TSInteraction *_Nullable latestCopy = [TSInteraction anyFetchWithUniqueId:message.uniqueId
                                                                          transaction:transaction];
            if (![latestCopy isKindOfClass:[TSOutgoingMessage class]]) {
                OWSLogWarn(@"Could not update expiration for deleted message.");
                return;
            }
            TSOutgoingMessage *latestMessage = (TSOutgoingMessage *)latestCopy;
            [ViewOnceMessages completeIfNecessaryWithMessage:latestMessage transaction:transaction];
        });
    }

    if (!message.shouldSyncTranscript) {
        return success();
    }

    [message sendSyncTranscript]
        .doneInBackground(^(id value) {
            OWSLogInfo(@"Successfully sent sync transcript.");

            DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                [message updateWithHasSyncedTranscript:YES transaction:transaction];
            });

            success();
        })
        .catchInBackground(^(NSError *error) {
            OWSLogInfo(@"Failed to send sync transcript: %@ (isRetryable: %d)", error, [error isRetryable]);

            failure(error);
        });
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
