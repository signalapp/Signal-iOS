//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageSender.h"
#import "ContactsUpdater.h"
#import "NSData+keyVersionByte.h"
#import "NSData+messagePadding.h"
#import "OWSBlockingManager.h"
#import "OWSDevice.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSError.h"
#import "OWSIdentityManager.h"
#import "OWSMessageServiceParams.h"
#import "OWSOutgoingSentMessageTranscript.h"
#import "OWSOutgoingSyncMessage.h"
#import "OWSUploadingService.h"
#import "PreKeyBundle+jsonDict.h"
#import "SignalRecipient.h"
#import "TSAccountManager.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TSIncomingMessage.h"
#import "TSInfoMessage.h"
#import "TSInvalidIdentityKeySendingErrorMessage.h"
#import "TSNetworkManager.h"
#import "TSOutgoingMessage.h"
#import "TSPreKeyManager.h"
#import "TSStorageManager+PreKeyStore.h"
#import "TSStorageManager+SignedPreKeyStore.h"
#import "TSStorageManager+sessionStore.h"
#import "TSStorageManager.h"
#import "TSThread.h"
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/CipherMessage.h>
#import <AxolotlKit/PreKeyBundle.h>
#import <AxolotlKit/SessionBuilder.h>
#import <AxolotlKit/SessionCipher.h>
#import <TwistedOakCollapsingFutures/CollapsingFutures.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

void AssertIsOnSendingQueue()
{
#ifdef DEBUG
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(10, 0)) {
        dispatch_assert_queue([OWSDispatch sendingQueue]);
    } // else, skip assert as it's a development convenience.
#endif
}

static void *kNSError_MessageSender_IsRetryable = &kNSError_MessageSender_IsRetryable;
static void *kNSError_MessageSender_ShouldBeIgnoredForGroups = &kNSError_MessageSender_ShouldBeIgnoredForGroups;
static void *kNSError_MessageSender_IsFatal = &kNSError_MessageSender_IsFatal;

// isRetryable and isFatal are opposites but not redundant.
//
// If a group message send fails, the send will be retried if any of the errors were retryable UNLESS
// any of the errors were fatal.  Fatal errors trump retryable errors.
@implementation NSError (OWSMessageSender)

- (BOOL)isRetryable
{
    NSNumber *value = objc_getAssociatedObject(self, kNSError_MessageSender_IsRetryable);
    // This value should always be set for all errors by the time OWSSendMessageOperation
    // queries it's value.  If not, default to retrying in production.
    OWSAssert(value);
    return value ? [value boolValue] : YES;
}

- (void)setIsRetryable:(BOOL)value
{
    objc_setAssociatedObject(self, kNSError_MessageSender_IsRetryable, @(value), OBJC_ASSOCIATION_COPY);
}

- (BOOL)shouldBeIgnoredForGroups
{
    NSNumber *value = objc_getAssociatedObject(self, kNSError_MessageSender_ShouldBeIgnoredForGroups);
    // This value will NOT always be set for all errors by the time we query it's value.
    // Default to NOT ignoring.
    return value ? [value boolValue] : NO;
}

- (void)setShouldBeIgnoredForGroups:(BOOL)value
{
    objc_setAssociatedObject(self, kNSError_MessageSender_ShouldBeIgnoredForGroups, @(value), OBJC_ASSOCIATION_COPY);
}

- (BOOL)isFatal
{
    NSNumber *value = objc_getAssociatedObject(self, kNSError_MessageSender_IsFatal);
    // This value will NOT always be set for all errors by the time we query it's value.
    // Default to NOT fatal.
    return value ? [value boolValue] : NO;
}

- (void)setIsFatal:(BOOL)value
{
    objc_setAssociatedObject(self, kNSError_MessageSender_IsFatal, @(value), OBJC_ASSOCIATION_COPY);
}

@end

#pragma mark -

/**
 * OWSSendMessageOperation encapsulates all the work associated with sending a message, e.g. uploading attachments,
 * getting proper keys, and retrying upon failure.
 *
 * Used by `OWSMessageSender` to serialize message sending, ensuring that messages are emitted in the order they
 * were sent.
 */
@interface OWSSendMessageOperation : NSOperation

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithMessage:(TSOutgoingMessage *)message
                  messageSender:(OWSMessageSender *)messageSender
                        success:(void (^)())successHandler
                        failure:(void (^)(NSError *_Nonnull error))failureHandler NS_DESIGNATED_INITIALIZER;

#pragma mark - background task mgmt

- (void)startBackgroundTask;
- (void)endBackgroundTask;

@end

#pragma mark -

typedef NS_ENUM(NSInteger, OWSSendMessageOperationState) {
    OWSSendMessageOperationStateNew,
    OWSSendMessageOperationStateExecuting,
    OWSSendMessageOperationStateFinished
};

@interface OWSMessageSender (OWSSendMessageOperation)

- (void)attemptToSendMessage:(TSOutgoingMessage *)message
                     success:(void (^)())successHandler
                     failure:(RetryableFailureHandler)failureHandler;

@end

#pragma mark -

NSString *const OWSSendMessageOperationKeyIsExecuting = @"isExecuting";
NSString *const OWSSendMessageOperationKeyIsFinished = @"isFinished";

NSUInteger const OWSSendMessageOperationMaxRetries = 4;

@interface OWSSendMessageOperation ()

@property (nonatomic, readonly) TSOutgoingMessage *message;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) void (^successHandler)();
@property (nonatomic, readonly) void (^failureHandler)(NSError *_Nonnull error);
@property (nonatomic) OWSSendMessageOperationState operationState;
@property (nonatomic) UIBackgroundTaskIdentifier backgroundTaskIdentifier;

@end

#pragma mark -

@implementation OWSSendMessageOperation

- (instancetype)initWithMessage:(TSOutgoingMessage *)message
                  messageSender:(OWSMessageSender *)messageSender
                        success:(void (^)())aSuccessHandler
                        failure:(void (^)(NSError *_Nonnull error))aFailureHandler
{
    self = [super init];
    if (!self) {
        return self;
    }

    _operationState = OWSSendMessageOperationStateNew;
    _backgroundTaskIdentifier = UIBackgroundTaskInvalid;

    _message = message;
    _messageSender = messageSender;

    __weak typeof(self) weakSelf = self;
    _successHandler = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            OWSProdCFail([OWSAnalyticsEvents messageSenderErrorSendOperationDidNotComplete]);
            return;
        }

        [message updateWithMessageState:TSOutgoingMessageStateSentToService];

        aSuccessHandler();

        [strongSelf markAsComplete];
    };

    _failureHandler = ^(NSError *_Nonnull error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            OWSProdCFail([OWSAnalyticsEvents messageSenderErrorSendOperationDidNotComplete]);
            return;
        }

        [strongSelf.message updateWithSendingError:error];

        DDLogDebug(@"%@ failed with error: %@", strongSelf.tag, error);
        aFailureHandler(error);

        [strongSelf markAsComplete];
    };

    return self;
}

#pragma mark - background task mgmt

// We want to make sure to finish sending any in-flight messages when the app is backgrounded.
// We have to call `startBackgroundTask` *before* the task is enqueued, since we can't guarantee when the operation will
// be dequeued.
- (void)startBackgroundTask
{
    AssertIsOnMainThread();
    OWSAssert(self.backgroundTaskIdentifier == UIBackgroundTaskInvalid);

    self.backgroundTaskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        DDLogWarn(@"%@ Timed out while in background trying to send message: %@", self.tag, self.message);
        [self endBackgroundTask];
    }];
}

- (void)endBackgroundTask
{
    [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTaskIdentifier];
}

- (void)setBackgroundTaskIdentifier:(UIBackgroundTaskIdentifier)backgroundTaskIdentifier
{
    AssertIsOnMainThread();

    // Should only be sent once per operation
    OWSAssert(_backgroundTaskIdentifier == UIBackgroundTaskInvalid);
    OWSAssert(backgroundTaskIdentifier != UIBackgroundTaskInvalid);

    _backgroundTaskIdentifier = backgroundTaskIdentifier;
}

#pragma mark - NSOperation overrides

- (BOOL)isExecuting
{
    return self.operationState == OWSSendMessageOperationStateExecuting;
}

- (BOOL)isFinished
{
    return self.operationState == OWSSendMessageOperationStateFinished;
}

- (void)start
{
    // Should call `startBackgroundTask` before enqueuing the operation
    // to ensure we don't get suspended before the operation completes.
    OWSAssert(self.backgroundTaskIdentifier != UIBackgroundTaskInvalid);

    [self willChangeValueForKey:OWSSendMessageOperationKeyIsExecuting];
    self.operationState = OWSSendMessageOperationStateExecuting;
    [self didChangeValueForKey:OWSSendMessageOperationKeyIsExecuting];
    [self main];
}

- (void)main
{
    [self tryWithRemainingRetries:OWSSendMessageOperationMaxRetries];
}

#pragma mark - methods

- (void)tryWithRemainingRetries:(NSUInteger)remainingRetries
{
    // Use this flag to ensure a given operation only succeeds or fails once.
    __block BOOL onceFlag = NO;
    RetryableFailureHandler retryableFailureHandler = ^(NSError *_Nonnull error) {
        DDLogInfo(@"%@ Sending failed. Remaining retries: %lu", self.tag, (unsigned long)remainingRetries);

        OWSAssert(!onceFlag);
        onceFlag = YES;

        if (![error isRetryable] || [error isFatal]) {
            DDLogInfo(@"%@ Skipping retry due to terminal error: %@", self.tag, error);
            self.failureHandler(error);
            return;
        }

        if (remainingRetries > 0) {
            [self tryWithRemainingRetries:remainingRetries - 1];
        } else {
            DDLogWarn(@"%@ Too many failures. Giving up sending.", self.tag);

            self.failureHandler(error);
        }
    };

    [self.messageSender attemptToSendMessage:self.message
                                     success:^{
                                         OWSAssert(!onceFlag);
                                         onceFlag = YES;

                                         self.successHandler();
                                     }
                                     failure:retryableFailureHandler];
}

- (void)markAsComplete
{
    [self willChangeValueForKey:OWSSendMessageOperationKeyIsExecuting];
    [self willChangeValueForKey:OWSSendMessageOperationKeyIsFinished];

    // Ensure we call the success or failure handler exactly once.
    @synchronized(self)
    {
        OWSAssert(self.operationState != OWSSendMessageOperationStateFinished);

        self.operationState = OWSSendMessageOperationStateFinished;
    }

    [self didChangeValueForKey:OWSSendMessageOperationKeyIsExecuting];
    [self didChangeValueForKey:OWSSendMessageOperationKeyIsFinished];

    [self endBackgroundTask];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end


int const OWSMessageSenderRetryAttempts = 3;
NSString *const OWSMessageSenderInvalidDeviceException = @"InvalidDeviceException";
NSString *const OWSMessageSenderRateLimitedException = @"RateLimitedException";

@interface OWSMessageSender ()

@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
@property (nonatomic, readonly) OWSUploadingService *uploadingService;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (nonatomic, readonly) id<ContactsManagerProtocol> contactsManager;
@property (nonatomic, readonly) ContactsUpdater *contactsUpdater;
@property (atomic, readonly) NSMutableDictionary<NSString *, NSOperationQueue *> *sendingQueueMap;

@end

@implementation OWSMessageSender

- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager
                        storageManager:(TSStorageManager *)storageManager
                       contactsManager:(id<ContactsManagerProtocol>)contactsManager
                       contactsUpdater:(ContactsUpdater *)contactsUpdater
{
    self = [super init];
    if (!self) {
        return self;
    }

    _networkManager = networkManager;
    _storageManager = storageManager;
    _contactsManager = contactsManager;
    _contactsUpdater = contactsUpdater;
    _sendingQueueMap = [NSMutableDictionary new];

    _uploadingService = [[OWSUploadingService alloc] initWithNetworkManager:networkManager];
    _dbConnection = storageManager.newDatabaseConnection;

    OWSSingletonAssert();

    return self;
}

- (void)setBlockingManager:(OWSBlockingManager *)blockingManager
{
    OWSAssert(blockingManager);
    OWSAssert(!_blockingManager);

    _blockingManager = blockingManager;
}

- (NSOperationQueue *)sendingQueueForMessage:(TSOutgoingMessage *)message
{
    OWSAssert(message);

    NSString *kDefaultQueueKey = @"kDefaultQueueKey";
    NSString *queueKey = message.uniqueThreadId ?: kDefaultQueueKey;
    OWSAssert(queueKey.length > 0);

    @synchronized(self)
    {
        NSOperationQueue *sendingQueue = self.sendingQueueMap[queueKey];

        if (!sendingQueue) {
            sendingQueue = [NSOperationQueue new];
            sendingQueue.qualityOfService = NSOperationQualityOfServiceUserInitiated;
            sendingQueue.maxConcurrentOperationCount = 1;

            self.sendingQueueMap[queueKey] = sendingQueue;
        }

        return sendingQueue;
    }
}

- (void)sendMessage:(TSOutgoingMessage *)message
            success:(void (^)())successHandler
            failure:(void (^)(NSError *error))failureHandler
{
    [self sendMessage:message transaction:nil success:successHandler failure:failureHandler];
}

- (void)sendMessage:(TSOutgoingMessage *)message
        transaction:(YapDatabaseReadWriteTransaction *_Nullable)transaction
            success:(void (^)())successHandler
            failure:(void (^)(NSError *error))failureHandler
{
    OWSAssert(message);

    if (transaction) {
        [message updateWithMessageState:TSOutgoingMessageStateAttemptingOut transaction:transaction];
    } else {
        [message updateWithMessageState:TSOutgoingMessageStateAttemptingOut];
    }
    OWSSendMessageOperation *sendMessageOperation = [[OWSSendMessageOperation alloc] initWithMessage:message
                                                                                       messageSender:self
                                                                                             success:successHandler
                                                                                             failure:failureHandler];

    // We call `startBackgroundTask` here to prevent our app from suspending while being backgrounded
    // until the operation is completed - at which point the OWSSendMessageOperation ends it's background task.
    [sendMessageOperation startBackgroundTask];

    NSOperationQueue *sendingQueue = [self sendingQueueForMessage:message];
    [sendingQueue addOperation:sendMessageOperation];
}

- (void)attemptToSendMessage:(TSOutgoingMessage *)message
                     success:(void (^)())successHandler
                     failure:(RetryableFailureHandler)failureHandler
{
    [self ensureAnyAttachmentsUploaded:message
        success:^() {
            [self deliverMessage:message
                         success:successHandler
                         failure:^(NSError *error) {
                             DDLogDebug(@"%@ Message send attempt failed: %@", self.tag, message.debugDescription);
                             failureHandler(error);
                         }];
        }
        failure:^(NSError *error) {
            DDLogDebug(@"%@ Attachment upload attempt failed: %@", self.tag, message.debugDescription);
            failureHandler(error);
        }];
}

- (void)ensureAnyAttachmentsUploaded:(TSOutgoingMessage *)message
                             success:(void (^)())successHandler
                             failure:(RetryableFailureHandler)failureHandler
{
    if (!message.hasAttachments) {
        return successHandler();
    }

    TSAttachmentStream *attachmentStream =
        [TSAttachmentStream fetchObjectWithUniqueID:message.attachmentIds.firstObject];

    if (!attachmentStream) {
        OWSProdError([OWSAnalyticsEvents messageSenderErrorCouldNotLoadAttachment]);
        NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
        // Not finding local attachment is a terminal failure.
        [error setIsRetryable:NO];
        return failureHandler(error);
    }

    [self.uploadingService uploadAttachmentStream:attachmentStream
                                          message:message
                                          success:successHandler
                                          failure:failureHandler];
}

- (void)sendTemporaryAttachmentData:(id<DataSource>)dataSource
                        contentType:(NSString *)contentType
                          inMessage:(TSOutgoingMessage *)message
                            success:(void (^)())successHandler
                            failure:(void (^)(NSError *error))failureHandler
{
    OWSAssert(dataSource);

    void (^successWithDeleteHandler)() = ^() {
        successHandler();

        DDLogDebug(@"Removing temporary attachment message.");
        [message remove];
    };

    void (^failureWithDeleteHandler)(NSError *error) = ^(NSError *error) {
        failureHandler(error);

        DDLogDebug(@"Removing temporary attachment message.");
        [message remove];
    };

    [self sendAttachmentData:dataSource
                 contentType:contentType
              sourceFilename:nil
                   inMessage:message
                     success:successWithDeleteHandler
                     failure:failureWithDeleteHandler];
}

- (void)sendAttachmentData:(id<DataSource>)dataSource
               contentType:(NSString *)contentType
            sourceFilename:(nullable NSString *)sourceFilename
                 inMessage:(TSOutgoingMessage *)message
                   success:(void (^)())successHandler
                   failure:(void (^)(NSError *error))failureHandler
{
    OWSAssert(dataSource);

    dispatch_async([OWSDispatch attachmentsQueue], ^{
        TSAttachmentStream *attachmentStream =
            [[TSAttachmentStream alloc] initWithContentType:contentType sourceFilename:sourceFilename];
        if (message.isVoiceMessage) {
            attachmentStream.attachmentType = TSAttachmentTypeVoiceMessage;
        }

        if (![attachmentStream writeDataSource:dataSource]) {
            OWSProdError([OWSAnalyticsEvents messageSenderErrorCouldNotWriteAttachment]);
            NSError *error = OWSErrorMakeWriteAttachmentDataError();
            return failureHandler(error);
        }

        [attachmentStream save];
        [message.attachmentIds addObject:attachmentStream.uniqueId];
        if (sourceFilename) {
            message.attachmentFilenameMap[attachmentStream.uniqueId] = sourceFilename;
        }
        [message save];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self sendMessage:message success:successHandler failure:failureHandler];
        });
    });
}

- (NSArray<SignalRecipient *> *)getRecipients:(NSArray<NSString *> *)identifiers error:(NSError **)error
{
    NSMutableArray<SignalRecipient *> *recipients = [NSMutableArray new];

    for (NSString *recipientId in identifiers) {
        SignalRecipient *existingRecipient = [SignalRecipient recipientWithTextSecureIdentifier:recipientId];

        if (existingRecipient) {
            [recipients addObject:existingRecipient];
        } else {
            SignalRecipient *newRecipient = [self.contactsUpdater synchronousLookup:recipientId error:error];
            if (newRecipient) {
                [recipients addObject:newRecipient];
            }
        }
    }

    if (recipients.count == 0 && !*error) {
        // error should be set in contactsUpater, but just in case.
        OWSProdError([OWSAnalyticsEvents messageSenderErrorCouldNotFindContacts1]);
        *error = OWSErrorMakeFailedToSendOutgoingMessageError();
    }

    return [recipients copy];
}

- (void)deliverMessage:(TSOutgoingMessage *)message
               success:(void (^)())successHandler
               failure:(RetryableFailureHandler)failureHandler
{
    TSThread *thread = message.thread;

    dispatch_async([OWSDispatch sendingQueue], ^{
        if ([thread isKindOfClass:[TSGroupThread class]]) {
            TSGroupThread *gThread = (TSGroupThread *)thread;

            NSError *error;
            NSArray<SignalRecipient *> *recipients =
                [self getRecipients:gThread.groupModel.groupMemberIds error:&error];

            if (recipients.count == 0) {
                if (!error) {
                    OWSProdError([OWSAnalyticsEvents messageSenderErrorCouldNotFindContacts2]);
                    error = OWSErrorMakeFailedToSendOutgoingMessageError();
                }
                // If no recipients were found, there's no reason to retry. It will just fail again.
                [error setIsRetryable:NO];
                failureHandler(error);
                return;
            }

            [self groupSend:recipients message:message thread:gThread success:successHandler failure:failureHandler];

        } else if ([thread isKindOfClass:[TSContactThread class]]
            || [message isKindOfClass:[OWSOutgoingSyncMessage class]]) {

            TSContactThread *contactThread = (TSContactThread *)thread;
            if ([contactThread.contactIdentifier isEqualToString:[TSAccountManager localNumber]]
                && ![message isKindOfClass:[OWSOutgoingSyncMessage class]]) {

                [self handleSendToMyself:message];
                successHandler();
                return;
            }

            NSString *recipientContactId = [message isKindOfClass:[OWSOutgoingSyncMessage class]]
                ? [TSAccountManager localNumber]
                : contactThread.contactIdentifier;

            // If we block a user, don't send 1:1 messages to them. The UI
            // should prevent this from occurring, but in some edge cases
            // you might, for example, have a pending outgoing message when
            // you block them.
            OWSAssert(recipientContactId.length > 0);
            NSArray<NSString *> *blockedPhoneNumbers = _blockingManager.blockedPhoneNumbers;
            if ([blockedPhoneNumbers containsObject:recipientContactId]) {
                DDLogInfo(@"%@ skipping 1:1 send to blocked contact: %@", self.tag, recipientContactId);
                NSError *error = OWSErrorMakeMessageSendFailedToBlockListError();
                // No need to retry - the user will continue to be blocked.
                [error setIsRetryable:NO];
                failureHandler(error);
                return;
            }

            SignalRecipient *recipient = [SignalRecipient recipientWithTextSecureIdentifier:recipientContactId];
            if (!recipient) {
                NSError *error;
                // possibly returns nil.
                recipient = [self.contactsUpdater synchronousLookup:recipientContactId error:&error];

                if (error) {
                    if (error.code == OWSErrorCodeNoSuchSignalRecipient) {
                        DDLogWarn(@"%@ recipient contact not found", self.tag);
                        [self unregisteredRecipient:recipient message:message thread:thread];
                    }

                    OWSProdError([OWSAnalyticsEvents messageSenderErrorCouldNotFindContacts3]);
                    // No need to repeat trying to find a failure. Apart from repeatedly failing, it would also cause us
                    // to print redundant error messages.
                    [error setIsRetryable:NO];
                    failureHandler(error);
                    return;
                }
            }

            if (!recipient) {
                NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
                DDLogWarn(@"recipient contact still not found after attempting lookup.");
                // No need to repeat trying to find a failure. Apart from repeatedly failing, it would also cause us to
                // print redundant error messages.
                [error setIsRetryable:NO];
                failureHandler(error);
                return;
            }

            [self sendMessage:message
                    recipient:recipient
                       thread:thread
                     attempts:OWSMessageSenderRetryAttempts
                      success:successHandler
                      failure:failureHandler];
        } else {
            // Neither a group nor contact thread? This should never happen.
            OWSFail(@"%@ Unknown message type: %@", self.tag, NSStringFromClass([message class]));

            NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
            [error setIsRetryable:NO];
            failureHandler(error);
        }
    });
}

// For group sends, we're using chained futures to make the code more readable.
- (TOCFuture *)sendMessageFuture:(TSOutgoingMessage *)message
                       recipient:(SignalRecipient *)recipient
                          thread:(TSThread *)thread
{
    TOCFutureSource *futureSource = [[TOCFutureSource alloc] init];

    [self sendMessage:message
        recipient:recipient
        thread:thread
        attempts:OWSMessageSenderRetryAttempts
        success:^{
            DDLogInfo(@"%@ Marking group message as sent to recipient: %@", self.tag, recipient.uniqueId);
            [message updateWithSentRecipient:recipient.uniqueId];
            [futureSource trySetResult:@1];
        }
        failure:^(NSError *error) {
            [futureSource trySetFailure:error];
        }];

    return futureSource.future;
}

- (void)groupSend:(NSArray<SignalRecipient *> *)recipients
          message:(TSOutgoingMessage *)message
           thread:(TSThread *)thread
          success:(void (^)())successHandler
          failure:(RetryableFailureHandler)failureHandler
{
    [self saveGroupMessage:message inThread:thread];
    NSMutableArray<TOCFuture *> *futures = [NSMutableArray array];

    for (SignalRecipient *recipient in recipients) {
        NSString *recipientId = recipient.recipientId;

        // We don't need to send the message to ourselves...
        if ([recipientId isEqualToString:[TSAccountManager localNumber]]) {
            continue;
        }
        // We don't need to sent the message to all group members if
        // it has a "single group recipient".
        if (message.singleGroupRecipient && ![message.singleGroupRecipient isEqualToString:recipientId]) {
            continue;
        }
        if ([message wasSentToRecipient:recipientId]) {
            // Skip recipients we have already sent this message to (on an
            // earlier retry, perhaps).
            DDLogInfo(@"%@ Skipping group message recipient; already sent: %@", self.tag, recipient.uniqueId);
            continue;
        }

        // ...otherwise we send.
        [futures addObject:[self sendMessageFuture:message recipient:recipient thread:thread]];
    }

    TOCFuture *completionFuture = futures.toc_thenAll;

    [completionFuture thenDo:^(id value) {
        successHandler();
    }];

    [completionFuture catchDo:^(id failure) {
        // failure from toc_thenAll yields an array of failed Futures, rather than the future's failure.
        NSError *firstRetryableError = nil;
        NSError *firstNonRetryableError = nil;

        if ([failure isKindOfClass:[NSArray class]]) {
            NSArray *groupSendFutures = (NSArray *)failure;
            for (TOCFuture *groupSendFuture in groupSendFutures) {
                if (groupSendFuture.hasFailed) {
                    id failureResult = groupSendFuture.forceGetFailure;
                    if ([failureResult isKindOfClass:[NSError class]]) {
                        NSError *error = failureResult;

                        // Some errors should be ignored when sending messages
                        // to groups.  See discussion on
                        // NSError (OWSMessageSender) category.
                        if ([error shouldBeIgnoredForGroups]) {
                            continue;
                        }

                        // Some errors should never be retried, in order to avoid
                        // hitting rate limits, for example.  Unfortunately, since
                        // group send retry is all-or-nothing, we need to fail
                        // immediately even if some of the other recipients had
                        // retryable errors.
                        if ([error isFatal]) {
                            failureHandler(error);
                            return;
                        }

                        if ([error isRetryable] && !firstRetryableError) {
                            firstRetryableError = error;
                        } else if (![error isRetryable] && !firstNonRetryableError) {
                            firstNonRetryableError = error;
                        }
                    }
                }
            }
        }

        // If any of the group send errors are retryable, we want to retry.
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
                NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeMessageSendNoValidRecipients,
                    NSLocalizedString(@"ERROR_DESCRIPTION_NO_VALID_RECIPIENTS",
                        @"Error indicating that an outgoing message had no valid recipients."));
                [error setIsRetryable:NO];
                failureHandler(error);
            } else {
                successHandler();
            }
        }
    }];
}

- (void)unregisteredRecipient:(SignalRecipient *)recipient
                      message:(TSOutgoingMessage *)message
                       thread:(TSThread *)thread
{
    [self.dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [recipient removeWithTransaction:transaction];
        [[TSInfoMessage userNotRegisteredMessageInThread:thread]
            saveWithTransaction:transaction];
    }];
}

- (void)sendMessage:(TSOutgoingMessage *)message
          recipient:(SignalRecipient *)recipient
             thread:(TSThread *)thread
           attempts:(int)remainingAttempts
            success:(void (^)())successHandler
            failure:(RetryableFailureHandler)failureHandler
{
    DDLogDebug(@"%@ sending message to service: %@", self.tag, message.debugDescription);
    AssertIsOnSendingQueue();

    if ([TSPreKeyManager isAppLockedDueToPreKeyUpdateFailures]) {
        OWSProdError([OWSAnalyticsEvents messageSendErrorFailedDueToPrekeyUpdateFailures]);

        // Retry prekey update every time user tries to send a message while app
        // is disabled due to prekey update failures.
        //
        // Only try to update the signed prekey; updating it is sufficient to
        // re-enable message sending.
        [TSPreKeyManager registerPreKeysWithMode:RefreshPreKeysMode_SignedOnly
            success:^{
                DDLogInfo(@"%@ New prekeys registered with server.", self.tag);
            }
            failure:^(NSError *error) {
                DDLogWarn(@"%@ Failed to update prekeys with the server: %@", self.tag, error);
            }];

        NSError *error = OWSErrorMakeMessageSendDisabledDueToPreKeyUpdateFailuresError();
        [error setIsRetryable:YES];
        return failureHandler(error);
    }

    if (remainingAttempts <= 0) {
        // We should always fail with a specific error.
        OWSProdFail([OWSAnalyticsEvents messageSenderErrorGenericSendFailure]);

        NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
        [error setIsRetryable:YES];
        return failureHandler(error);
    }
    remainingAttempts -= 1;

    NSArray<NSDictionary *> *deviceMessages;
    @try {
        deviceMessages = [self deviceMessages:message forRecipient:recipient inThread:thread];
    } @catch (NSException *exception) {
        deviceMessages = @[];
        if ([exception.name isEqualToString:UntrustedIdentityKeyException]) {
            // This *can* happen under normal usage, but it should happen relatively rarely.
            // We expect it to happen whenever Bob reinstalls, and Alice messages Bob before
            // she can pull down his latest identity.
            // If it's happening a lot, we should rethink our profile fetching strategy.
            OWSProdInfo([OWSAnalyticsEvents messageSendErrorFailedDueToUntrustedKey]);

            NSString *localizedErrorDescriptionFormat
                = NSLocalizedString(@"FAILED_SENDING_BECAUSE_UNTRUSTED_IDENTITY_KEY",
                    @"action sheet header when re-sending message which failed because of untrusted identity keys");

            NSString *localizedErrorDescription =
                [NSString stringWithFormat:localizedErrorDescriptionFormat,
                          [self.contactsManager displayNameForPhoneIdentifier:recipient.recipientId]];
            NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeUntrustedIdentityKey, localizedErrorDescription);

            // Key will continue to be unaccepted, so no need to retry. It'll only cause us to hit the Pre-Key request
            // rate limit
            [error setIsRetryable:NO];
            // Avoid the "Too many failures with this contact" error rate limiting.
            [error setIsFatal:YES];

            PreKeyBundle *newKeyBundle = exception.userInfo[TSInvalidPreKeyBundleKey];
            if (![newKeyBundle isKindOfClass:[PreKeyBundle class]]) {
                OWSProdFail([OWSAnalyticsEvents messageSenderErrorUnexpectedKeyBundle]);
                failureHandler(error);
                return;
            }

            NSData *newIdentityKeyWithVersion = newKeyBundle.identityKey;

            if (![newIdentityKeyWithVersion isKindOfClass:[NSData class]]) {
                OWSProdFail([OWSAnalyticsEvents messageSenderErrorInvalidIdentityKeyType]);
                failureHandler(error);
                return;
            }

            // TODO migrate to storing the full 33 byte representation of the identity key.
            if (newIdentityKeyWithVersion.length != kIdentityKeyLength) {
                OWSProdFail([OWSAnalyticsEvents messageSenderErrorInvalidIdentityKeyLength]);
                failureHandler(error);
                return;
            }

            NSData *newIdentityKey = [newIdentityKeyWithVersion removeKeyType];

            [[OWSIdentityManager sharedManager] saveRemoteIdentity:newIdentityKey recipientId:recipient.recipientId];

            failureHandler(error);
            return;
        }

        if ([exception.name isEqualToString:OWSMessageSenderRateLimitedException]) {
            NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeSignalServiceRateLimited,
                NSLocalizedString(@"FAILED_SENDING_BECAUSE_RATE_LIMIT",
                    @"action sheet header when re-sending message which failed because of too many attempts"));

            // We're already rate-limited. No need to exacerbate the problem.
            [error setIsRetryable:NO];
            // Avoid exacerbating the rate limiting.
            [error setIsFatal:YES];
            return failureHandler(error);
        }

        if (remainingAttempts == 0) {
            DDLogWarn(
                @"%@ Terminal failure to build any device messages. Giving up with exception:%@", self.tag, exception);
            NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
            // Since we've already repeatedly failed to build messages, it's unlikely that repeating the whole process
            // will succeed.
            [error setIsRetryable:NO];
            return failureHandler(error);
        }
    }

    NSString *localNumber = [TSAccountManager localNumber];
    if ([localNumber isEqualToString:recipient.uniqueId]) {
        if (deviceMessages.count < 1) {
            DDLogInfo(@"Ignoring sync message without linked devices: %@", [message class]);
            OWSAssert([message isKindOfClass:[OWSOutgoingSyncMessage class]]);

            dispatch_async([OWSDispatch sendingQueue], ^{
                [recipient save];
                [self handleMessageSentLocally:message];
                successHandler();
            });

            return;
        }
    } else {
        OWSAssert(deviceMessages.count > 0);
    }


    TSSubmitMessageRequest *request = [[TSSubmitMessageRequest alloc] initWithRecipient:recipient.uniqueId
                                                                               messages:deviceMessages
                                                                                  relay:recipient.relay
                                                                              timeStamp:message.timestamp];

    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            dispatch_async([OWSDispatch sendingQueue], ^{
                [recipient save];
                [self handleMessageSentLocally:message];
                successHandler();
            });
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            DDLogInfo(@"%@ sending to recipient: %@, failed with error: %@", self.tag, recipient.uniqueId, error);
            [DDLog flushLog];

            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            long statuscode = response.statusCode;
            NSData *responseData = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];

            void (^retrySend)() = ^void() {
                if (remainingAttempts <= 0) {
                    // Since we've already repeatedly failed to send to the messaging API,
                    // it's unlikely that repeating the whole process will succeed.
                    [error setIsRetryable:NO];
                    return failureHandler(error);
                }

                dispatch_async([OWSDispatch sendingQueue], ^{
                    DDLogDebug(@"%@ Retrying: %@", self.tag, message.debugDescription);
                    [self sendMessage:message
                            recipient:recipient
                               thread:thread
                             attempts:remainingAttempts
                              success:successHandler
                              failure:failureHandler];
                });
            };

            switch (statuscode) {
                case 401: {
                    DDLogWarn(@"%@ Unable to send due to invalid credentials. Did the user's client get de-authed by registering elsewhere?", self.tag);
                    NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeSignalServiceFailure, NSLocalizedString(@"ERROR_DESCRIPTION_SENDING_UNAUTHORIZED", @"Error message when attempting to send message"));
                    // No need to retry if we've been de-authed.
                    [error setIsRetryable:NO];
                    return failureHandler(error);
                }
                case 404: {
                    DDLogWarn(@"%@ Unregistered recipient: %@", self.tag, recipient.uniqueId);

                    [self unregisteredRecipient:recipient message:message thread:thread];
                    NSError *error = OWSErrorMakeNoSuchSignalRecipientError();
                    // No need to retry if the recipient is not registered.
                    [error setIsRetryable:NO];
                    // If one member of a group deletes their account,
                    // the group should ignore errors when trying to send
                    // messages to this ex-member.
                    [error setShouldBeIgnoredForGroups:YES];
                    return failureHandler(error);
                }
                case 409: {
                    // Mismatched devices
                    DDLogWarn(@"%@ Mismatch Devices for recipient: %@", self.tag, recipient.uniqueId);

                    NSError *error;
                    NSDictionary *serializedResponse =
                        [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&error];
                    if (error) {
                        OWSProdError([OWSAnalyticsEvents messageSenderErrorCouldNotParseMismatchedDevicesJson]);
                        [error setIsRetryable:YES];
                        return failureHandler(error);
                    }

                    [self handleMismatchedDevices:serializedResponse recipient:recipient completion:retrySend];
                    break;
                }
                case 410: {
                    // Stale devices
                    DDLogWarn(@"%@ Stale devices for recipient: %@", self.tag, recipient.uniqueId);

                    if (!responseData) {
                        DDLogWarn(@"Stale devices but server didn't specify devices in response.");
                        NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                        [error setIsRetryable:YES];
                        return failureHandler(error);
                    }

                    [self handleStaleDevicesWithResponse:responseData
                                             recipientId:recipient.uniqueId
                                              completion:retrySend];
                    break;
                }
                default:
                    retrySend();
                    break;
            }
        }];
}

- (void)handleMismatchedDevices:(NSDictionary *)dictionary
                      recipient:(SignalRecipient *)recipient
                     completion:(void (^)())completionHandler
{
    NSArray *extraDevices = [dictionary objectForKey:@"extraDevices"];
    NSArray *missingDevices = [dictionary objectForKey:@"missingDevices"];

    dispatch_async([OWSDispatch sessionStoreQueue], ^{
        if (extraDevices.count < 1 && missingDevices.count < 1) {
            OWSProdFail([OWSAnalyticsEvents messageSenderErrorNoMissingOrExtraDevices]);
        }

        if (extraDevices && extraDevices.count > 0) {
            DDLogInfo(@"%@ removing extra devices: %@", self.tag, extraDevices);
            for (NSNumber *extraDeviceId in extraDevices) {
                [self.storageManager deleteSessionForContact:recipient.uniqueId deviceId:extraDeviceId.intValue];
            }

            [recipient removeDevices:[NSSet setWithArray:extraDevices]];
        }

        if (missingDevices && missingDevices.count > 0) {
            DDLogInfo(@"%@ Adding missing devices: %@", self.tag, missingDevices);
            [recipient addDevices:[NSSet setWithArray:missingDevices]];
        }

        [recipient save];
        completionHandler();
    });
}

- (void)handleMessageSentLocally:(TSOutgoingMessage *)message
{
    if (message.shouldSyncTranscript) {
        // TODO: I suspect we shouldn't optimistically set hasSyncedTranscript.
        //       We could set this in a success handler for [sendSyncTranscriptForMessage:].
        [message updateWithHasSyncedTranscript:YES];
        [self sendSyncTranscriptForMessage:message];
    }

    [OWSDisappearingMessagesJob setExpirationForMessage:message];
}

- (void)handleMessageSentRemotely:(TSOutgoingMessage *)message
                           sentAt:(uint64_t)sentAt
                      transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(message);
    OWSAssert(transaction);

    [message updateWithWasSentAndDeliveredWithTransaction:transaction];
    [self becomeConsistentWithDisappearingConfigurationForMessage:message];
    [OWSDisappearingMessagesJob setExpirationForMessage:message expirationStartedAt:sentAt];
}

- (void)becomeConsistentWithDisappearingConfigurationForMessage:(TSOutgoingMessage *)outgoingMessage
{
    [OWSDisappearingMessagesJob becomeConsistentWithConfigurationForMessage:outgoingMessage
                                                            contactsManager:self.contactsManager];
}

- (void)handleSendToMyself:(TSOutgoingMessage *)outgoingMessage
{
    [self handleMessageSentLocally:outgoingMessage];

    if (!(outgoingMessage.body || outgoingMessage.hasAttachments)) {
        DDLogDebug(
            @"%@ Refusing to make incoming copy of non-standard message sent to self:%@", self.tag, outgoingMessage);
        return;
    }

    // Getting the local number uses a transaction, so we need to do that before we
    // create a new transaction to avoid deadlock.
    NSString *contactId = [TSAccountManager localNumber];
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSContactThread *cThread =
            [TSContactThread getOrCreateThreadWithContactId:contactId transaction:transaction];
        [cThread saveWithTransaction:transaction];
        TSIncomingMessage *incomingMessage =
            [[TSIncomingMessage alloc] initWithTimestamp:(outgoingMessage.timestamp + 1)
                                                inThread:cThread
                                                authorId:[cThread contactIdentifier]
                                          sourceDeviceId:[OWSDevice currentDeviceId]
                                             messageBody:outgoingMessage.body
                                           attachmentIds:outgoingMessage.attachmentIds
                                        expiresInSeconds:outgoingMessage.expiresInSeconds];
        [incomingMessage saveWithTransaction:transaction];
    }];
}

- (void)sendSyncTranscriptForMessage:(TSOutgoingMessage *)message
{
    OWSOutgoingSentMessageTranscript *sentMessageTranscript =
        [[OWSOutgoingSentMessageTranscript alloc] initWithOutgoingMessage:message];

    [self sendMessage:sentMessageTranscript
        recipient:[SignalRecipient selfRecipient]
        thread:message.thread
        attempts:OWSMessageSenderRetryAttempts
        success:^{
            DDLogInfo(@"Succesfully sent sync transcript.");
        }
        failure:^(NSError *error) {
            // FIXME: We don't yet honor the isRetryable flag here, since sendSyncTranscriptForMessage
            // isn't yet wrapped in our retryable SendMessageOperation. Addressing this would require
            // a refactor to the MessageSender. Note that we *do* however continue to respect the
            // OWSMessageSenderRetryAttempts, which is an "inner" retry loop, encompassing only the
            // messaging API.
            DDLogInfo(@"Failed to send sync transcript: %@ (isRetryable: %d)", error, [error isRetryable]);
        }];
}

- (NSArray<NSDictionary *> *)deviceMessages:(TSOutgoingMessage *)message
                               forRecipient:(SignalRecipient *)recipient
                                   inThread:(TSThread *)thread
{
    NSMutableArray *messagesArray = [NSMutableArray arrayWithCapacity:recipient.devices.count];

    NSData *plainText = [message buildPlainTextData:recipient];
    DDLogDebug(@"%@ built message: %@ plainTextData.length: %lu", self.tag, [message class], (unsigned long)plainText.length);

    for (NSNumber *deviceNumber in recipient.devices) {
        @try {
            __block NSDictionary *messageDict;
            __block NSException *encryptionException;
            // Mutating session state is not thread safe, so we operate on a serial queue, shared with decryption
            // operations.
            dispatch_sync([OWSDispatch sessionStoreQueue], ^{
                @try {
                    messageDict = [self encryptedMessageWithPlaintext:plainText
                                                          toRecipient:recipient.uniqueId
                                                             deviceId:deviceNumber
                                                        keyingStorage:[TSStorageManager sharedManager]];
                } @catch (NSException *exception) {
                    encryptionException = exception;
                }
            });

            if (encryptionException) {
                DDLogInfo(@"%@ Exception during encryption: %@", self.tag, encryptionException);
                @throw encryptionException;
            }

            if (messageDict) {
                [messagesArray addObject:messageDict];
            } else {
                @throw [NSException exceptionWithName:InvalidMessageException
                                               reason:@"Failed to encrypt message"
                                             userInfo:nil];
            }
        } @catch (NSException *exception) {
            if ([exception.name isEqualToString:OWSMessageSenderInvalidDeviceException]) {
                [recipient removeDevices:[NSSet setWithObject:deviceNumber]];
            } else {
                @throw exception;
            }
        }
    }

    return [messagesArray copy];
}

- (NSDictionary *)encryptedMessageWithPlaintext:(NSData *)plainText
                                    toRecipient:(NSString *)identifier
                                       deviceId:(NSNumber *)deviceNumber
                                  keyingStorage:(TSStorageManager *)storage
{
    if (![storage containsSession:identifier deviceId:[deviceNumber intValue]]) {
        __block dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        __block PreKeyBundle *_Nullable bundle;
        __block NSException *_Nullable exception;
        [self.networkManager makeRequest:[[TSRecipientPrekeyRequest alloc] initWithRecipient:identifier
                                                                                    deviceId:[deviceNumber stringValue]]
            success:^(NSURLSessionDataTask *task, id responseObject) {
                bundle = [PreKeyBundle preKeyBundleFromDictionary:responseObject forDeviceNumber:deviceNumber];
                dispatch_semaphore_signal(sema);
            }
            failure:^(NSURLSessionDataTask *task, NSError *error) {
                if (!IsNSErrorNetworkFailure(error)) {
                    OWSProdError([OWSAnalyticsEvents messageSenderErrorRecipientPrekeyRequestFailed]);
                }
                DDLogError(@"Server replied to PreKeyBundle request with error: %@", error);
                NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
                if (response.statusCode == 404) {
                    // Can't throw exception from within callback as it's probabably a different thread.
                    exception = [NSException exceptionWithName:OWSMessageSenderInvalidDeviceException
                                                        reason:@"Device not registered"
                                                      userInfo:nil];
                } else if (response.statusCode == 413) {
                    // Can't throw exception from within callback as it's probabably a different thread.
                    exception = [NSException exceptionWithName:OWSMessageSenderRateLimitedException
                                                        reason:@"Too many prekey requests"
                                                      userInfo:nil];
                }
                dispatch_semaphore_signal(sema);
            }];
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        if (exception) {
            @throw exception;
        }

        if (!bundle) {
            @throw [NSException exceptionWithName:InvalidVersionException
                                           reason:@"Can't get a prekey bundle from the server with required information"
                                         userInfo:nil];
        } else {
            SessionBuilder *builder = [[SessionBuilder alloc] initWithSessionStore:storage
                                                                       preKeyStore:storage
                                                                 signedPreKeyStore:storage
                                                                  identityKeyStore:[OWSIdentityManager sharedManager]
                                                                       recipientId:identifier
                                                                          deviceId:[deviceNumber intValue]];
            @try {
                // Mutating session state is not thread safe.
                @synchronized(self) {
                    [builder processPrekeyBundle:bundle];
                }
            } @catch (NSException *exception) {
                if ([exception.name isEqualToString:UntrustedIdentityKeyException]) {
                    @throw [NSException
                        exceptionWithName:UntrustedIdentityKeyException
                                   reason:nil
                                 userInfo:@{ TSInvalidPreKeyBundleKey : bundle, TSInvalidRecipientKey : identifier }];
                }
                @throw exception;
            }
        }
    }

    SessionCipher *cipher = [[SessionCipher alloc] initWithSessionStore:storage
                                                            preKeyStore:storage
                                                      signedPreKeyStore:storage
                                                       identityKeyStore:[OWSIdentityManager sharedManager]
                                                            recipientId:identifier
                                                               deviceId:[deviceNumber intValue]];

    id<CipherMessage> encryptedMessage = [cipher encryptMessage:[plainText paddedMessageBody]];


    NSData *serializedMessage = encryptedMessage.serialized;
    TSWhisperMessageType messageType = [self messageTypeForCipherMessage:encryptedMessage];

    OWSMessageServiceParams *messageParams = [[OWSMessageServiceParams alloc] initWithType:messageType
                                                                               recipientId:identifier
                                                                                    device:[deviceNumber intValue]
                                                                                   content:serializedMessage
                                                                            registrationId:cipher.remoteRegistrationId];

    NSError *error;
    NSDictionary *jsonDict = [MTLJSONAdapter JSONDictionaryFromModel:messageParams error:&error];

    if (error) {
        OWSProdError([OWSAnalyticsEvents messageSendErrorCouldNotSerializeMessageJson]);
        return nil;
    }

    return jsonDict;
}

- (TSWhisperMessageType)messageTypeForCipherMessage:(id<CipherMessage>)cipherMessage
{
    if ([cipherMessage isKindOfClass:[PreKeyWhisperMessage class]]) {
        return TSPreKeyWhisperMessageType;
    } else if ([cipherMessage isKindOfClass:[WhisperMessage class]]) {
        return TSEncryptedWhisperMessageType;
    }
    return TSUnknownMessageType;
}

- (void)saveGroupMessage:(TSOutgoingMessage *)message inThread:(TSThread *)thread
{
    if (message.groupMetaMessage == TSGroupMessageDeliver) {
        // TODO: Why is this necessary?
        [message save];
    } else if (message.groupMetaMessage == TSGroupMessageQuit) {
        [[[TSInfoMessage alloc] initWithTimestamp:message.timestamp
                                         inThread:thread
                                      messageType:TSInfoMessageTypeGroupQuit
                                    customMessage:message.customMessage] save];
    } else {
        [[[TSInfoMessage alloc] initWithTimestamp:message.timestamp
                                         inThread:thread
                                      messageType:TSInfoMessageTypeGroupUpdate
                                    customMessage:message.customMessage] save];
    }
}

// Called when the server indicates that the devices no longer exist - e.g. when the remote recipient has reinstalled.
- (void)handleStaleDevicesWithResponse:(NSData *)responseData
                           recipientId:(NSString *)identifier
                            completion:(void (^)())completionHandler
{
    dispatch_async([OWSDispatch sendingQueue], ^{
        NSDictionary *serialization = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil];
        NSArray *devices = serialization[@"staleDevices"];

        if (!([devices count] > 0)) {
            return;
        }

        dispatch_async([OWSDispatch sessionStoreQueue], ^{
            for (NSUInteger i = 0; i < [devices count]; i++) {
                int deviceNumber = [devices[i] intValue];
                [[TSStorageManager sharedManager] deleteSessionForContact:identifier deviceId:deviceNumber];
            }
            completionHandler();
        });
    });
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
