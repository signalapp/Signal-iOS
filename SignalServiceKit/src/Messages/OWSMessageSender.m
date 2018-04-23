//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageSender.h"
#import "AppContext.h"
#import "ContactsUpdater.h"
#import "NSData+keyVersionByte.h"
#import "NSData+messagePadding.h"
#import "NSDate+OWS.h"
#import "NSError+MessageSending.h"
#import "OWSBackgroundTask.h"
#import "OWSBlockingManager.h"
#import "OWSDevice.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSError.h"
#import "OWSIdentityManager.h"
#import "OWSMessageServiceParams.h"
#import "OWSOperation.h"
#import "OWSOutgoingSentMessageTranscript.h"
#import "OWSOutgoingSyncMessage.h"
#import "OWSPrimaryStorage+PreKeyStore.h"
#import "OWSPrimaryStorage+SignedPreKeyStore.h"
#import "OWSPrimaryStorage+sessionStore.h"
#import "OWSPrimaryStorage.h"
#import "OWSRequestFactory.h"
#import "OWSUploadOperation.h"
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
#import "TSQuotedMessage.h"
#import "TSThread.h"
#import "Threading.h"
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/CipherMessage.h>
#import <AxolotlKit/PreKeyBundle.h>
#import <AxolotlKit/SessionBuilder.h>
#import <AxolotlKit/SessionCipher.h>
#import <TwistedOakCollapsingFutures/CollapsingFutures.h>

NS_ASSUME_NONNULL_BEGIN

const NSUInteger kOversizeTextMessageSizeThreshold = 2 * 1024;

void AssertIsOnSendingQueue()
{
#ifdef DEBUG
    if (@available(iOS 10.0, *)) {
        dispatch_assert_queue([OWSDispatch sendingQueue]);
    } // else, skip assert as it's a development convenience.
#endif
}

#pragma mark -

/**
 * OWSSendMessageOperation encapsulates all the work associated with sending a message, e.g. uploading attachments,
 * getting proper keys, and retrying upon failure.
 *
 * Used by `OWSMessageSender` to serialize message sending, ensuring that messages are emitted in the order they
 * were sent.
 */
@interface OWSSendMessageOperation : OWSOperation

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithMessage:(TSOutgoingMessage *)message
                  messageSender:(OWSMessageSender *)messageSender
                   dbConnection:(YapDatabaseConnection *)dbConnection
                        success:(void (^)(void))aSuccessHandler
                        failure:(void (^)(NSError *_Nonnull error))aFailureHandler NS_DESIGNATED_INITIALIZER;

@end

#pragma mark -

@interface OWSMessageSender (OWSSendMessageOperation)

- (void)sendMessageToService:(TSOutgoingMessage *)message
                     success:(void (^)(void))successHandler
                     failure:(RetryableFailureHandler)failureHandler;

@end

#pragma mark -

@interface OWSSendMessageOperation ()

@property (nonatomic, readonly) TSOutgoingMessage *message;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (nonatomic, readonly) void (^successHandler)(void);
@property (nonatomic, readonly) void (^failureHandler)(NSError *_Nonnull error);

@end

#pragma mark -

@implementation OWSSendMessageOperation

- (instancetype)initWithMessage:(TSOutgoingMessage *)message
                  messageSender:(OWSMessageSender *)messageSender
                   dbConnection:(YapDatabaseConnection *)dbConnection
                        success:(void (^)(void))successHandler
                        failure:(void (^)(NSError *_Nonnull error))failureHandler
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.remainingRetries = 6;
    _message = message;
    _messageSender = messageSender;
    _dbConnection = dbConnection;
    _successHandler = successHandler;
    _failureHandler = failureHandler;

    return self;
}

#pragma mark - OWSOperation overrides

- (nullable NSError *)checkForPreconditionError
{
    for (NSOperation *dependency in self.dependencies) {
        if (![dependency isKindOfClass:[OWSOperation class]]) {
            NSString *errorDescription =
                [NSString stringWithFormat:@"%@ unknown dependency: %@", self.logTag, dependency.class];
            NSError *assertionError = OWSErrorMakeAssertionError(errorDescription);
            return assertionError;
        }

        OWSOperation *upload = (OWSOperation *)dependency;

        // Cannot proceed if dependency failed - surface the dependency's error.
        NSError *_Nullable dependencyError = upload.failingError;
        if (dependencyError) {
            return dependencyError;
        }
    }

    // Sanity check preconditions
    if (self.message.hasAttachments) {
        [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
            TSAttachmentStream *attachmentStream
                = (TSAttachmentStream *)[self.message attachmentWithTransaction:transaction];
            OWSAssert(attachmentStream);
            OWSAssert([attachmentStream isKindOfClass:[TSAttachmentStream class]]);
            OWSAssert(attachmentStream.serverId);
            OWSAssert(attachmentStream.isUploaded);
        }];
    }

    return nil;
}

- (void)run
{
    // If the message has been deleted, abort send.
    if (self.message.shouldBeSaved && ![TSOutgoingMessage fetchObjectWithUniqueID:self.message.uniqueId]) {
        DDLogInfo(@"%@ aborting message send; message deleted.", self.logTag);
        NSError *error = OWSErrorWithCodeDescription(
            OWSErrorCodeMessageDeletedBeforeSent, @"Message was deleted before it could be sent.");
        error.isFatal = YES;
        [self reportError:error];
        return;
    }

    [self.messageSender sendMessageToService:self.message
        success:^{
            [self reportSuccess];
        }
        failure:^(NSError *error) {
            [self reportError:error];
        }];
}

- (void)didSucceed
{
    OWSAssert(self.message.messageState == TSOutgoingMessageStateSent);

    self.successHandler();
}

- (void)didFailWithError:(NSError *)error
{
    [self.message updateWithSendingError:error];
    
    DDLogDebug(@"%@ failed with error: %@", self.logTag, error);
    self.failureHandler(error);
}

@end

int const OWSMessageSenderRetryAttempts = 3;
NSString *const OWSMessageSenderInvalidDeviceException = @"InvalidDeviceException";
NSString *const OWSMessageSenderRateLimitedException = @"RateLimitedException";

@interface OWSMessageSender ()

@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) OWSPrimaryStorage *primaryStorage;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (nonatomic, readonly) id<ContactsManagerProtocol> contactsManager;
@property (nonatomic, readonly) ContactsUpdater *contactsUpdater;
@property (atomic, readonly) NSMutableDictionary<NSString *, NSOperationQueue *> *sendingQueueMap;

@end

@implementation OWSMessageSender

- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager
                        primaryStorage:(OWSPrimaryStorage *)primaryStorage
                       contactsManager:(id<ContactsManagerProtocol>)contactsManager
                       contactsUpdater:(ContactsUpdater *)contactsUpdater
{
    self = [super init];
    if (!self) {
        return self;
    }

    _networkManager = networkManager;
    _primaryStorage = primaryStorage;
    _contactsManager = contactsManager;
    _contactsUpdater = contactsUpdater;
    _sendingQueueMap = [NSMutableDictionary new];
    _dbConnection = primaryStorage.newDatabaseConnection;

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

    if ([kDefaultQueueKey isEqualToString:queueKey]) {
        // when do we get here?
        DDLogDebug(@"%@ using default message queue", self.logTag);
    }

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

- (void)enqueueMessage:(TSOutgoingMessage *)message
               success:(void (^)(void))successHandler
               failure:(void (^)(NSError *error))failureHandler
{
    OWSAssert(message);
    if (message.body.length > 0) {
        OWSAssert([message.body lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= kOversizeTextMessageSizeThreshold);
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        __block NSArray<TSAttachmentStream *> *quotedThumbnailAttachments = @[];

        // This method will use a read/write transaction. This transaction
        // will block until any open read/write transactions are complete.
        //
        // That's key - we don't want to send any messages in response
        // to an incoming message until processing of that batch of messages
        // is complete.  For example, we wouldn't want to auto-reply to a
        // group info request before that group info request's batch was
        // finished processing.  Otherwise, we might receive a delivery
        // notice for a group update we hadn't yet saved to the db.
        //
        // So we're using YDB behavior to ensure this invariant, which is a bit
        // unorthodox.
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            if (message.quotedMessage) {
                quotedThumbnailAttachments =
                    [message.quotedMessage createThumbnailAttachmentsIfNecessaryWithTransaction:transaction];
            }

            // All outgoing messages should be saved at the time they are enqueued.
            [message saveWithTransaction:transaction];
            // When we start a message send, all "failed" recipients should be marked as "sending".
            [message updateWithMarkingAllUnsentRecipientsAsSendingWithTransaction:transaction];
        }];

        NSOperationQueue *sendingQueue = [self sendingQueueForMessage:message];
        OWSSendMessageOperation *sendMessageOperation =
            [[OWSSendMessageOperation alloc] initWithMessage:message
                                               messageSender:self
                                                dbConnection:self.dbConnection
                                                     success:successHandler
                                                     failure:failureHandler];
        if (message.hasAttachments) {
            OWSUploadOperation *uploadAttachmentOperation =
                [[OWSUploadOperation alloc] initWithAttachmentId:message.attachmentIds.firstObject
                                                    dbConnection:self.dbConnection];
            [sendMessageOperation addDependency:uploadAttachmentOperation];
            [sendingQueue addOperation:uploadAttachmentOperation];
        }

        // Though we currently only ever expect at most one thumbnail, the proto data model
        // suggests this could change. The logic is intended to work with multiple, but
        // if we ever actually want to send multiple, we should do more testing.
        OWSAssert(quotedThumbnailAttachments.count <= 1);
        for (TSAttachmentStream *thumbnailAttachment in quotedThumbnailAttachments) {
            OWSAssert(message.quotedMessage);

            OWSUploadOperation *uploadQuoteThumbnailOperation =
                [[OWSUploadOperation alloc] initWithAttachmentId:thumbnailAttachment.uniqueId
                                                    dbConnection:self.dbConnection];

            // TODO put attachment uploads on a (lowly) concurrent queue
            [sendMessageOperation addDependency:uploadQuoteThumbnailOperation];
            [sendingQueue addOperation:uploadQuoteThumbnailOperation];
        }

        [sendingQueue addOperation:sendMessageOperation];
    });
}

- (void)enqueueTemporaryAttachment:(DataSource *)dataSource
                       contentType:(NSString *)contentType
                         inMessage:(TSOutgoingMessage *)message
                           success:(void (^)(void))successHandler
                           failure:(void (^)(NSError *error))failureHandler
{
    OWSAssert(dataSource);

    void (^successWithDeleteHandler)(void) = ^() {
        successHandler();

        DDLogDebug(@"%@ Removing successful temporary attachment message with attachment ids: %@",
            self.logTag,
            message.attachmentIds);
        [message remove];
    };

    void (^failureWithDeleteHandler)(NSError *error) = ^(NSError *error) {
        failureHandler(error);

        DDLogDebug(@"%@ Removing failed temporary attachment message with attachment ids: %@",
            self.logTag,
            message.attachmentIds);
        [message remove];
    };

    [self enqueueAttachment:dataSource
                contentType:contentType
             sourceFilename:nil
                  inMessage:message
                    success:successWithDeleteHandler
                    failure:failureWithDeleteHandler];
}

- (void)enqueueAttachment:(DataSource *)dataSource
              contentType:(NSString *)contentType
           sourceFilename:(nullable NSString *)sourceFilename
                inMessage:(TSOutgoingMessage *)message
                  success:(void (^)(void))successHandler
                  failure:(void (^)(NSError *error))failureHandler
{
    OWSAssert(dataSource);

    dispatch_async([OWSDispatch attachmentsQueue], ^{
        TSAttachmentStream *attachmentStream =
            [[TSAttachmentStream alloc] initWithContentType:contentType
                                                  byteCount:(UInt32)dataSource.dataLength
                                             sourceFilename:sourceFilename];
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

        [self enqueueMessage:message success:successHandler failure:failureHandler];
    });
}

- (NSArray<SignalRecipient *> *)getRecipientsForRecipientIds:(NSArray<NSString *> *)recipientIds error:(NSError **)error
{
    OWSAssert(error);

    error = nil;

    NSMutableArray<SignalRecipient *> *recipients = [NSMutableArray new];

    for (NSString *recipientId in recipientIds) {
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

- (void)sendMessageToService:(TSOutgoingMessage *)message
                     success:(void (^)(void))successHandler
                     failure:(RetryableFailureHandler)failureHandler
{
    dispatch_async([OWSDispatch sendingQueue], ^{
        TSThread *thread = message.thread;

        if ([thread isKindOfClass:[TSGroupThread class]]) {

            TSGroupThread *gThread = (TSGroupThread *)thread;

            // Send to the intersection of:
            //
            // * "sending" recipients of the message.
            // * members of the group.
            //
            // I.e. try to send a message IFF:
            //
            // * The recipient was in the group when the message was first tried to be sent.
            // * The recipient is still in the group.
            // * The recipient is in the "sending" state.
            NSMutableSet<NSString *> *obsoleteRecipientIds = [NSMutableSet setWithArray:message.sendingRecipientIds];
            [obsoleteRecipientIds minusSet:[NSSet setWithArray:gThread.groupModel.groupMemberIds]];
            if (obsoleteRecipientIds.count > 0) {
                [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    for (NSString *recipientId in obsoleteRecipientIds) {
                        // Mark this recipient as "skipped".
                        //
                        // TODO: We should also mark as "skipped" group members who no longer have signal accounts.
                        [message updateWithSkippedRecipient:recipientId transaction:transaction];
                    }
                }];
            }

            NSMutableSet<NSString *> *sendingRecipientIds = [NSMutableSet setWithArray:message.sendingRecipientIds];
            [sendingRecipientIds intersectSet:[NSSet setWithArray:gThread.groupModel.groupMemberIds]];

            NSError *error;
            NSArray<SignalRecipient *> *recipients =
                [self getRecipientsForRecipientIds:sendingRecipientIds.allObjects error:&error];

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
            if ([self.blockingManager isRecipientIdBlocked:recipientContactId]) {
                DDLogInfo(@"%@ skipping 1:1 send to blocked contact: %@", self.logTag, recipientContactId);
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
                        DDLogWarn(@"%@ recipient contact not found", self.logTag);
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

            [self sendMessageToService:message
                             recipient:recipient
                                thread:thread
                              attempts:OWSMessageSenderRetryAttempts
                               success:successHandler
                               failure:failureHandler];
        } else {
            // Neither a group nor contact thread? This should never happen.
            OWSFail(@"%@ Unknown message type: %@", self.logTag, NSStringFromClass([message class]));

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

    [self sendMessageToService:message
        recipient:recipient
        thread:thread
        attempts:OWSMessageSenderRetryAttempts
        success:^{
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
          success:(void (^)(void))successHandler
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
        if (![message.sendingRecipientIds containsObject:recipientId]) {
            // Skip recipients we have already sent this message to (on an
            // earlier retry, perhaps).
            DDLogInfo(@"%@ Skipping group message recipient; already sent: %@", self.logTag, recipient.uniqueId);
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

- (void)sendMessageToService:(TSOutgoingMessage *)message
                   recipient:(SignalRecipient *)recipient
                      thread:(TSThread *)thread
                    attempts:(int)remainingAttempts
                     success:(void (^)(void))successHandler
                     failure:(RetryableFailureHandler)failureHandler
{
    DDLogInfo(@"%@ attempting to send message: %@, timestamp: %llu, recipient: %@",
        self.logTag,
        message.class,
        message.timestamp,
        recipient.uniqueId);
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
                DDLogInfo(@"%@ New prekeys registered with server.", self.logTag);
            }
            failure:^(NSError *error) {
                DDLogWarn(@"%@ Failed to update prekeys with the server: %@", self.logTag, error);
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
        deviceMessages = [self deviceMessages:message forRecipient:recipient];
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
            NSError *error = OWSErrorMakeUntrustedIdentityError(localizedErrorDescription, recipient.recipientId);

            // Key will continue to be unaccepted, so no need to retry. It'll only cause us to hit the Pre-Key request
            // rate limit
            [error setIsRetryable:NO];
            // Avoid the "Too many failures with this contact" error rate limiting.
            [error setIsFatal:YES];

            PreKeyBundle *_Nullable newKeyBundle = exception.userInfo[TSInvalidPreKeyBundleKey];
            if (newKeyBundle == nil) {
                OWSProdFail([OWSAnalyticsEvents messageSenderErrorMissingNewPreKeyBundle]);
                failureHandler(error);
                return;
            }

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
            DDLogWarn(@"%@ Terminal failure to build any device messages. Giving up with exception:%@",
                self.logTag,
                exception);
            NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
            // Since we've already repeatedly failed to build messages, it's unlikely that repeating the whole process
            // will succeed.
            [error setIsRetryable:NO];
            return failureHandler(error);
        }
    }

    NSString *localNumber = [TSAccountManager localNumber];
    BOOL isLocalNumber = [localNumber isEqualToString:recipient.uniqueId];
    if (isLocalNumber) {
        OWSAssert([message isKindOfClass:[OWSOutgoingSyncMessage class]]);
        // Messages sent to the "local number" should be sync messages.
        //
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

        // 1. Check OWSDevice's state.
        BOOL mayHaveLinkedDevices = [OWSDeviceManager.sharedManager mayHaveLinkedDevices:self.dbConnection];

        // 2. Check SignalRecipient's state.
        BOOL hasDeviceMessages = deviceMessages.count > 0;

        DDLogInfo(@"%@ mayHaveLinkedDevices: %d, hasDeviceMessages: %d",
            self.logTag,
            mayHaveLinkedDevices,
            hasDeviceMessages);

        if (!mayHaveLinkedDevices && !hasDeviceMessages) {
            DDLogInfo(@"%@ Ignoring sync message without secondary devices: %@", self.logTag, [message class]);
            OWSAssert([message isKindOfClass:[OWSOutgoingSyncMessage class]]);

            dispatch_async([OWSDispatch sendingQueue], ^{
                // This emulates the completion logic of an actual successful save (see below).
                [recipient save];
                successHandler();
            });

            return;
        } else if (mayHaveLinkedDevices) {
            // We may have just linked a new secondary device which is not yet reflected in
            // the SignalRecipient that corresponds to ourself.  Proceed.  Client should learn
            // of new secondary devices via 409 "Mismatched devices" response.
            DDLogWarn(@"%@ sync message has no device messages but account has secondary devices.", self.logTag);
        } else if (hasDeviceMessages) {
            OWSFail(@"%@ sync message has device messages for unknown secondary devices.", self.logTag);
        } else {
            // Account has secondary devices; proceed as usual.
        }
    } else {
        OWSAssert(deviceMessages.count > 0);
    }

    if (deviceMessages.count == 0) {
        // This might happen:
        //
        // * The first (after upgrading?) time we send a sync message to our linked devices.
        // * After unlinking all linked devices.
        // * After trying and failing to link a device.
        //
        // When we're not sure if we have linked devices, we need to try
        // to send self-sync messages even if they have no device messages
        // so that we can learn from the service whether or not there are
        // linked devices that we don't know about.
        DDLogWarn(@"%@ Sending a message with no device messages.", self.logTag);
    }

    TSRequest *request = [OWSRequestFactory submitMessageRequestWithRecipient:recipient.uniqueId
                                                                     messages:deviceMessages
                                                                        relay:recipient.relay
                                                                    timeStamp:message.timestamp];
    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            if (isLocalNumber && deviceMessages.count == 0) {
                DDLogInfo(@"%@ Sent a message with no device messages; clearing 'mayHaveLinkedDevices'.", self.logTag);
                // In order to avoid skipping necessary sync messages, the default value
                // for mayHaveLinkedDevices is YES.  Once we've successfully sent a
                // sync message with no device messages (e.g. the service has confirmed
                // that we have no linked devices), we can set mayHaveLinkedDevices to NO
                // to avoid unnecessary message sends for sync messages until we learn
                // of a linked device (e.g. through the device linking UI or by receiving
                // a sync message, etc.).
                [OWSDeviceManager.sharedManager clearMayHaveLinkedDevicesIfNotSet];
            }

            dispatch_async([OWSDispatch sendingQueue], ^{
                [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    [recipient saveWithTransaction:transaction];
                    [message updateWithSentRecipient:recipient.uniqueId transaction:transaction];
                }];

                [self handleMessageSentLocally:message];
                successHandler();
            });
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            DDLogInfo(@"%@ sending to recipient: %@, failed with error.", self.logTag, recipient.uniqueId);
            [DDLog flushLog];

            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            long statuscode = response.statusCode;
            NSData *responseData = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];

            void (^retrySend)(void) = ^void() {
                if (remainingAttempts <= 0) {
                    // Since we've already repeatedly failed to send to the messaging API,
                    // it's unlikely that repeating the whole process will succeed.
                    [error setIsRetryable:NO];
                    return failureHandler(error);
                }

                dispatch_async([OWSDispatch sendingQueue], ^{
                    DDLogDebug(@"%@ Retrying: %@", self.logTag, message.debugDescription);
                    [self sendMessageToService:message
                                     recipient:recipient
                                        thread:thread
                                      attempts:remainingAttempts
                                       success:successHandler
                                       failure:failureHandler];
                });
            };

            switch (statuscode) {
                case 401: {
                    DDLogWarn(@"%@ Unable to send due to invalid credentials. Did the user's client get de-authed by "
                              @"registering elsewhere?",
                        self.logTag);
                    NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeSignalServiceFailure, NSLocalizedString(@"ERROR_DESCRIPTION_SENDING_UNAUTHORIZED", @"Error message when attempting to send message"));
                    // No need to retry if we've been de-authed.
                    [error setIsRetryable:NO];
                    return failureHandler(error);
                }
                case 404: {
                    DDLogWarn(@"%@ Unregistered recipient: %@", self.logTag, recipient.uniqueId);

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
                    DDLogWarn(@"%@ Mismatch Devices for recipient: %@", self.logTag, recipient.uniqueId);

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
                    DDLogWarn(@"%@ Stale devices for recipient: %@", self.logTag, recipient.uniqueId);

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
                     completion:(void (^)(void))completionHandler
{
    NSArray *extraDevices = [dictionary objectForKey:@"extraDevices"];
    NSArray *missingDevices = [dictionary objectForKey:@"missingDevices"];

    if (missingDevices.count > 0) {
        NSString *localNumber = [TSAccountManager localNumber];
        if ([localNumber isEqualToString:recipient.uniqueId]) {
            [OWSDeviceManager.sharedManager setMayHaveLinkedDevices];
        }
    }

    [self.dbConnection
        asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            if (extraDevices.count < 1 && missingDevices.count < 1) {
                OWSProdFail([OWSAnalyticsEvents messageSenderErrorNoMissingOrExtraDevices]);
            }

            if (extraDevices && extraDevices.count > 0) {
                DDLogInfo(@"%@ removing extra devices: %@", self.logTag, extraDevices);
                for (NSNumber *extraDeviceId in extraDevices) {
                    [self.primaryStorage deleteSessionForContact:recipient.uniqueId
                                                        deviceId:extraDeviceId.intValue
                                                 protocolContext:transaction];
                }

                [recipient removeDevices:[NSSet setWithArray:extraDevices]];
            }

            if (missingDevices && missingDevices.count > 0) {
                DDLogInfo(@"%@ Adding missing devices: %@", self.logTag, missingDevices);
                [recipient addDevices:[NSSet setWithArray:missingDevices]];
            }

            [recipient saveWithTransaction:transaction];

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                completionHandler();
            });
        }];
}

- (void)handleMessageSentLocally:(TSOutgoingMessage *)message
{
    if (message.shouldSyncTranscript) {
        // TODO: I suspect we shouldn't optimistically set hasSyncedTranscript.
        //       We could set this in a success handler for [sendSyncTranscriptForMessage:].
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [message updateWithHasSyncedTranscript:YES transaction:transaction];
        }];
        [self sendSyncTranscriptForMessage:message];
    }

    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [[OWSDisappearingMessagesJob sharedJob] startAnyExpirationForMessage:message
                                                         expirationStartedAt:[NSDate ows_millisecondTimeStamp]
                                                                 transaction:transaction];
    }];
}

- (void)handleSendToMyself:(TSOutgoingMessage *)outgoingMessage
{
    [self handleMessageSentLocally:outgoingMessage];

    if (!(outgoingMessage.body || outgoingMessage.hasAttachments)) {
        // We only want to "clone" text and attachment messages.
        //
        // This method shouldn't be called for sync messages, so this
        // probably represents a bug.
        OWSFail(@"%@ Refusing to make incoming copy of non-standard message sent to self: %@",
            self.logTag,
            outgoingMessage);
        return;
    }

    // Getting the local number uses a transaction, so we need to do that before we
    // create a new transaction to avoid deadlock.
    NSString *contactId = [TSAccountManager localNumber];
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSContactThread *cThread =
            [TSContactThread getOrCreateThreadWithContactId:contactId transaction:transaction];
        [cThread saveWithTransaction:transaction];

        // We need to clone any attachments for message sent to self; otherwise deleting
        // the incoming or outgoing copy of the message will break the other.
        NSMutableArray<NSString *> *attachmentIds = [NSMutableArray new];
        for (NSString *attachmentId in outgoingMessage.attachmentIds) {
            TSAttachmentStream *_Nullable outgoingAttachment =
                [TSAttachmentStream fetchObjectWithUniqueID:attachmentId transaction:transaction];
            OWSAssert(outgoingAttachment);
            if (!outgoingAttachment) {
                DDLogError(@"%@ Couldn't load outgoing attachment for message sent to self.", self.logTag);
            } else {
                TSAttachmentStream *incomingAttachment =
                    [[TSAttachmentStream alloc] initWithContentType:outgoingAttachment.contentType
                                                          byteCount:outgoingAttachment.byteCount
                                                     sourceFilename:outgoingAttachment.sourceFilename];
                NSError *error;
                NSData *_Nullable data = [outgoingAttachment readDataFromFileWithError:&error];
                if (!data || error) {
                    DDLogError(@"%@ Couldn't load attachment data for message sent to self: %@.", self.logTag, error);
                } else {
                    [incomingAttachment writeData:data error:&error];
                    if (error) {
                        DDLogError(
                            @"%@ Couldn't copy attachment data for message sent to self: %@.", self.logTag, error);
                    } else {
                        [incomingAttachment saveWithTransaction:transaction];
                        [attachmentIds addObject:incomingAttachment.uniqueId];
                    }
                }
            }
        }

        // We want the incoming message to appear after the outgoing message.
        TSIncomingMessage *incomingMessage =
            [[TSIncomingMessage alloc] initIncomingMessageWithTimestamp:(outgoingMessage.timestamp + 1)
                                                               inThread:cThread
                                                               authorId:[cThread contactIdentifier]
                                                         sourceDeviceId:[OWSDevice currentDeviceId]
                                                            messageBody:outgoingMessage.body
                                                          attachmentIds:attachmentIds
                                                       expiresInSeconds:outgoingMessage.expiresInSeconds
                                                          quotedMessage:outgoingMessage.quotedMessage];
        [incomingMessage saveWithTransaction:transaction];
    }];
}

- (void)sendSyncTranscriptForMessage:(TSOutgoingMessage *)message
{
    OWSOutgoingSentMessageTranscript *sentMessageTranscript =
        [[OWSOutgoingSentMessageTranscript alloc] initWithOutgoingMessage:message];

    [self sendMessageToService:sentMessageTranscript
        recipient:[SignalRecipient selfRecipient]
        thread:message.thread
        attempts:OWSMessageSenderRetryAttempts
        success:^{
            DDLogInfo(@"Successfully sent sync transcript.");
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
{
    OWSAssert(message);
    OWSAssert(recipient);

    NSMutableArray *messagesArray = [NSMutableArray arrayWithCapacity:recipient.devices.count];

    NSData *plainText = [message buildPlainTextData:recipient];
    DDLogDebug(@"%@ built message: %@ plainTextData.length: %lu",
        self.logTag,
        [message class],
        (unsigned long)plainText.length);

    for (NSNumber *deviceNumber in recipient.devices) {
        @try {
            __block NSDictionary *messageDict;
            __block NSException *encryptionException;
            [self.dbConnection
                readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    @try {
                        messageDict = [self encryptedMessageWithPlaintext:plainText
                                                              toRecipient:recipient.uniqueId
                                                                 deviceId:deviceNumber
                                                            keyingStorage:self.primaryStorage
                                                                 isSilent:message.isSilent
                                                              transaction:transaction];
                    } @catch (NSException *exception) {
                        encryptionException = exception;
                    }
                }];

            if (encryptionException) {
                DDLogInfo(@"%@ Exception during encryption: %@", self.logTag, encryptionException);
                @throw encryptionException;
            }

            if (messageDict) {
                [messagesArray addObject:messageDict];
            } else {
                OWSRaiseException(InvalidMessageException, @"Failed to encrypt message");
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
                                  keyingStorage:(OWSPrimaryStorage *)storage
                                       isSilent:(BOOL)isSilent
                                    transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(plainText);
    OWSAssert(identifier.length > 0);
    OWSAssert(deviceNumber);
    OWSAssert(storage);
    OWSAssert(transaction);

    if (![storage containsSession:identifier deviceId:[deviceNumber intValue] protocolContext:transaction]) {
        __block dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        __block PreKeyBundle *_Nullable bundle;
        __block NSException *_Nullable exception;
        // It's not ideal that we're using a semaphore inside a read/write transaction.
        // To avoid deadlock, we need to ensure that our success/failure completions
        // are called _off_ the main thread.  Otherwise we'll deadlock if the main
        // thread is blocked on opening a transaction.
        TSRequest *request =
            [OWSRequestFactory recipientPrekeyRequestWithRecipient:identifier deviceId:[deviceNumber stringValue]];
        [self.networkManager makeRequest:request
            completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
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
        // FIXME: Currently this happens within a readwrite transaction - meaning our read-write transaction blocks
        // on a network request.
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        if (exception) {
            @throw exception;
        }

        if (!bundle) {
            OWSRaiseException(
                InvalidVersionException, @"Can't get a prekey bundle from the server with required information");
        } else {
            SessionBuilder *builder = [[SessionBuilder alloc] initWithSessionStore:storage
                                                                       preKeyStore:storage
                                                                 signedPreKeyStore:storage
                                                                  identityKeyStore:[OWSIdentityManager sharedManager]
                                                                       recipientId:identifier
                                                                          deviceId:[deviceNumber intValue]];
            @try {
                [builder processPrekeyBundle:bundle protocolContext:transaction];
            } @catch (NSException *exception) {
                if ([exception.name isEqualToString:UntrustedIdentityKeyException]) {
                    OWSRaiseExceptionWithUserInfo(UntrustedIdentityKeyException,
                        (@{ TSInvalidPreKeyBundleKey : bundle, TSInvalidRecipientKey : identifier }),
                        @"");
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

    id<CipherMessage> encryptedMessage =
        [cipher encryptMessage:[plainText paddedMessageBody] protocolContext:transaction];


    NSData *serializedMessage = encryptedMessage.serialized;
    TSWhisperMessageType messageType = [self messageTypeForCipherMessage:encryptedMessage];

    OWSMessageServiceParams *messageParams =
        [[OWSMessageServiceParams alloc] initWithType:messageType
                                          recipientId:identifier
                                               device:[deviceNumber intValue]
                                              content:serializedMessage
                                             isSilent:isSilent
                                       registrationId:[cipher remoteRegistrationId:transaction]];

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
                            completion:(void (^)(void))completionHandler
{
    dispatch_async([OWSDispatch sendingQueue], ^{
        NSDictionary *serialization = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil];
        NSArray *devices = serialization[@"staleDevices"];

        if (!([devices count] > 0)) {
            return;
        }

        [self.dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            for (NSUInteger i = 0; i < [devices count]; i++) {
                int deviceNumber = [devices[i] intValue];
                [[OWSPrimaryStorage sharedManager] deleteSessionForContact:identifier
                                                                  deviceId:deviceNumber
                                                           protocolContext:transaction];
            }
        }];
        completionHandler();
    });
}

@end

NS_ASSUME_NONNULL_END
