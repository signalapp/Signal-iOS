//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageSender.h"
#import "AppContext.h"
#import "NSData+keyVersionByte.h"
#import "NSData+messagePadding.h"
#import "NSDate+OWS.h"
#import "NSError+MessageSending.h"
#import "OWSBackgroundTask.h"
#import "OWSBlockingManager.h"
#import "OWSContact.h"
#import "OWSDevice.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSDispatch.h"
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
#import "SSKEnvironment.h"
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
#import "TSSocketManager.h"
#import "TSThread.h"
#import "Threading.h"
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/CipherMessage.h>
#import <AxolotlKit/PreKeyBundle.h>
#import <AxolotlKit/SessionBuilder.h>
#import <AxolotlKit/SessionCipher.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

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
                        failure:(void (^)(NSError * error))aFailureHandler NS_DESIGNATED_INITIALIZER;

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
@property (nonatomic, readonly) void (^failureHandler)(NSError * error);

@end

#pragma mark -

@implementation OWSSendMessageOperation

- (instancetype)initWithMessage:(TSOutgoingMessage *)message
                  messageSender:(OWSMessageSender *)messageSender
                   dbConnection:(YapDatabaseConnection *)dbConnection
                        success:(void (^)(void))successHandler
                        failure:(void (^)(NSError * error))failureHandler
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
    NSError *_Nullable error = [super checkForPreconditionError];
    if (error) {
        return error;
    }

    // Sanity check preconditions
    if (self.message.hasAttachments) {
        [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction * transaction) {
            TSAttachmentStream *attachmentStream
                = (TSAttachmentStream *)[self.message attachmentWithTransaction:transaction];
            OWSAssertDebug(attachmentStream);
            OWSAssertDebug([attachmentStream isKindOfClass:[TSAttachmentStream class]]);
            OWSAssertDebug(attachmentStream.serverId);
            OWSAssertDebug(attachmentStream.isUploaded);
        }];
    }

    return nil;
}

- (void)run
{
    // If the message has been deleted, abort send.
    if (self.message.shouldBeSaved && ![TSOutgoingMessage fetchObjectWithUniqueID:self.message.uniqueId]) {
        OWSLogInfo(@"aborting message send; message deleted.");
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
    if (self.message.messageState != TSOutgoingMessageStateSent) {
        OWSFailDebug(@"unexpected message status: %@", self.message.statusDescription);
    }

    self.successHandler();
}

- (void)didFailWithError:(NSError *)error
{
    [self.message updateWithSendingError:error];

    OWSLogDebug(@"failed with error: %@", error);
    self.failureHandler(error);
}

@end

int const OWSMessageSenderRetryAttempts = 3;
NSString *const OWSMessageSenderInvalidDeviceException = @"InvalidDeviceException";
NSString *const OWSMessageSenderRateLimitedException = @"RateLimitedException";

@interface OWSMessageSender ()

@property (nonatomic, readonly) OWSPrimaryStorage *primaryStorage;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (atomic, readonly) NSMutableDictionary<NSString *, NSOperationQueue *> *sendingQueueMap;

@end

@implementation OWSMessageSender

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];
    if (!self) {
        return self;
    }

    _primaryStorage = primaryStorage;
    _sendingQueueMap = [NSMutableDictionary new];
    _dbConnection = primaryStorage.newDatabaseConnection;

    OWSSingletonAssert();

    return self;
}

- (id<ContactsManagerProtocol>)contactsManager
{
    OWSAssertDebug(SSKEnvironment.shared.contactsManager);

    return SSKEnvironment.shared.contactsManager;
}

- (OWSBlockingManager *)blockingManager
{
    OWSAssertDebug(SSKEnvironment.shared.blockingManager);

    return SSKEnvironment.shared.blockingManager;
}

- (TSNetworkManager *)networkManager
{
    OWSAssertDebug(SSKEnvironment.shared.networkManager);

    return SSKEnvironment.shared.networkManager;
}

- (NSOperationQueue *)sendingQueueForMessage:(TSOutgoingMessage *)message
{
    OWSAssertDebug(message);


    NSString *kDefaultQueueKey = @"kDefaultQueueKey";
    NSString *queueKey = message.uniqueThreadId ?: kDefaultQueueKey;
    OWSAssertDebug(queueKey.length > 0);

    if ([kDefaultQueueKey isEqualToString:queueKey]) {
        // when do we get here?
        OWSLogDebug(@"using default message queue");
    }

    @synchronized(self)
    {
        NSOperationQueue *sendingQueue = self.sendingQueueMap[queueKey];

        if (!sendingQueue) {
            sendingQueue = [NSOperationQueue new];
            sendingQueue.qualityOfService = NSOperationQualityOfServiceUserInitiated;
            sendingQueue.maxConcurrentOperationCount = 1;
            sendingQueue.name = [NSString stringWithFormat:@"%@:%@", self.logTag, queueKey];
            self.sendingQueueMap[queueKey] = sendingQueue;
        }

        return sendingQueue;
    }
}

- (void)enqueueMessage:(TSOutgoingMessage *)message
               success:(void (^)(void))successHandler
               failure:(void (^)(NSError *error))failureHandler
{
    OWSAssertDebug(message);
    if (message.body.length > 0) {
        OWSAssertDebug([message.body lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= kOversizeTextMessageSizeThreshold);
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        __block NSArray<TSAttachmentStream *> *quotedThumbnailAttachments = @[];
        __block TSAttachmentStream *_Nullable contactShareAvatarAttachment;

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

            if (message.contactShare.avatarAttachmentId != nil) {
                TSAttachment *avatarAttachment = [message.contactShare avatarAttachmentWithTransaction:transaction];
                if ([avatarAttachment isKindOfClass:[TSAttachmentStream class]]) {
                    contactShareAvatarAttachment = (TSAttachmentStream *)avatarAttachment;
                } else {
                    OWSFailDebug(@"unexpected avatarAttachment: %@", avatarAttachment);
                }
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

        // TODO de-dupe attachment enque logic.
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
        OWSAssertDebug(quotedThumbnailAttachments.count <= 1);
        for (TSAttachmentStream *thumbnailAttachment in quotedThumbnailAttachments) {
            OWSAssertDebug(message.quotedMessage);

            OWSUploadOperation *uploadQuoteThumbnailOperation =
                [[OWSUploadOperation alloc] initWithAttachmentId:thumbnailAttachment.uniqueId
                                                    dbConnection:self.dbConnection];

            // TODO put attachment uploads on a (lowly) concurrent queue
            [sendMessageOperation addDependency:uploadQuoteThumbnailOperation];
            [sendingQueue addOperation:uploadQuoteThumbnailOperation];
        }

        if (contactShareAvatarAttachment != nil) {
            OWSAssertDebug(message.contactShare);
            OWSUploadOperation *uploadAvatarOperation =
                [[OWSUploadOperation alloc] initWithAttachmentId:contactShareAvatarAttachment.uniqueId
                                                    dbConnection:self.dbConnection];

            // TODO put attachment uploads on a (lowly) concurrent queue
            [sendMessageOperation addDependency:uploadAvatarOperation];
            [sendingQueue addOperation:uploadAvatarOperation];
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
    OWSAssertDebug(dataSource);

    void (^successWithDeleteHandler)(void) = ^() {
        successHandler();

        OWSLogDebug(@"Removing successful temporary attachment message with attachment ids: %@", message.attachmentIds);
        [message remove];
    };

    void (^failureWithDeleteHandler)(NSError *error) = ^(NSError *error) {
        failureHandler(error);

        OWSLogDebug(@"Removing failed temporary attachment message with attachment ids: %@", message.attachmentIds);
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
    OWSAssertDebug(dataSource);

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

- (NSArray<SignalRecipient *> *)signalRecipientsForRecipientIds:(NSArray<NSString *> *)recipientIds
                                                        message:(TSOutgoingMessage *)message
{
    OWSAssertDebug(recipientIds);
    OWSAssertDebug(message);

    NSMutableArray<SignalRecipient *> *recipients = [NSMutableArray new];
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        for (NSString *recipientId in recipientIds) {
            SignalRecipient *recipient =
                [SignalRecipient getOrBuildUnsavedRecipientForRecipientId:recipientId transaction:transaction];
            [recipients addObject:recipient];
        }
    }];
    return recipients;
}

- (void)sendMessageToService:(TSOutgoingMessage *)message
                     success:(void (^)(void))successHandler
                     failure:(RetryableFailureHandler)failureHandler
{
    dispatch_async([OWSDispatch sendingQueue], ^{
        TSThread *_Nullable thread = message.thread;

        // TODO: It would be nice to combine the "contact" and "group" send logic here.
        if ([thread isKindOfClass:[TSContactThread class]] &&
            [((TSContactThread *)thread).contactIdentifier isEqualToString:[TSAccountManager localNumber]]) {
            // Send to self.
            OWSAssertDebug(message.recipientIds.count == 1);
            [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                for (NSString *recipientId in message.sendingRecipientIds) {
                    [message updateWithReadRecipientId:recipientId
                                         readTimestamp:message.timestampForSorting
                                           transaction:transaction];
                }
            }];

            [self handleMessageSentLocally:message];

            successHandler();
            return;
        } else if ([thread isKindOfClass:[TSGroupThread class]]) {

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

            NSMutableSet<NSString *> *sendingRecipientIds = [NSMutableSet setWithArray:message.sendingRecipientIds];
            [sendingRecipientIds intersectSet:[NSSet setWithArray:gThread.groupModel.groupMemberIds]];
            [sendingRecipientIds minusSet:[NSSet setWithArray:self.blockingManager.blockedPhoneNumbers]];

            // Mark skipped recipients as such.  We skip because:
            //
            // * Recipient is no longer in the group.
            // * Recipient is blocked.
            //
            // Elsewhere, we skip recipient if their Signal account has been deactivated.
            NSMutableSet<NSString *> *obsoleteRecipientIds = [NSMutableSet setWithArray:message.sendingRecipientIds];
            [obsoleteRecipientIds minusSet:sendingRecipientIds];
            if (obsoleteRecipientIds.count > 0) {
                [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    for (NSString *recipientId in obsoleteRecipientIds) {
                        // Mark this recipient as "skipped".
                        [message updateWithSkippedRecipient:recipientId transaction:transaction];
                    }
                }];
            }

            if (sendingRecipientIds.count < 1) {
                // All recipients are already sent or can be skipped.
                successHandler();
                return;
            }

            NSArray<SignalRecipient *> *recipients =
                [self signalRecipientsForRecipientIds:sendingRecipientIds.allObjects message:message];
            OWSAssertDebug(recipients.count == sendingRecipientIds.count);

            [self groupSend:recipients message:message thread:gThread success:successHandler failure:failureHandler];

        } else if ([thread isKindOfClass:[TSContactThread class]]
            || [message isKindOfClass:[OWSOutgoingSyncMessage class]]) {

            TSContactThread *contactThread = (TSContactThread *)thread;

            NSString *recipientContactId
                = ([message isKindOfClass:[OWSOutgoingSyncMessage class]] ? [TSAccountManager localNumber]
                                                                          : contactThread.contactIdentifier);

            // If we block a user, don't send 1:1 messages to them. The UI
            // should prevent this from occurring, but in some edge cases
            // you might, for example, have a pending outgoing message when
            // you block them.
            OWSAssertDebug(recipientContactId.length > 0);
            if ([self.blockingManager isRecipientIdBlocked:recipientContactId]) {
                OWSLogInfo(@"skipping 1:1 send to blocked contact: %@", recipientContactId);
                NSError *error = OWSErrorMakeMessageSendFailedToBlockListError();
                // No need to retry - the user will continue to be blocked.
                [error setIsRetryable:NO];
                failureHandler(error);
                return;
            }

            NSArray<SignalRecipient *> *recipients =
            [self signalRecipientsForRecipientIds:@[recipientContactId] message:message];
            OWSAssertDebug(recipients.count == 1);
            SignalRecipient *recipient = recipients.firstObject;

            if (!recipient) {
                NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
                OWSLogWarn(@"recipient contact still not found after attempting lookup.");
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
                useWebsocketIfAvailable:YES
                                success:successHandler
                                failure:failureHandler];
        } else {
            // Neither a group nor contact thread? This should never happen.
            OWSFailDebug(@"Unknown message type: %@", [message class]);

            NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
            [error setIsRetryable:NO];
            failureHandler(error);
        }
    });
}

- (void)groupSend:(NSArray<SignalRecipient *> *)recipients
          message:(TSOutgoingMessage *)message
           thread:(TSThread *)thread
          success:(void (^)(void))successHandler
          failure:(RetryableFailureHandler)failureHandler
{
    [self saveGroupMessage:message inThread:thread];

    NSMutableArray<AnyPromise *> *sendPromises = [NSMutableArray array];
    NSMutableArray<NSError *> *sendErrors = [NSMutableArray array];

    for (SignalRecipient *recipient in recipients) {
        NSString *recipientId = recipient.recipientId;

        // We don't need to send the message to ourselves...
        if ([recipientId isEqualToString:[TSAccountManager localNumber]]) {
            continue;
        }

        // ...otherwise we send.

        // For group sends, we're using chained promises to make the code more readable.
        AnyPromise *sendPromise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
            [self sendMessageToService:message
                recipient:recipient
                thread:thread
                attempts:OWSMessageSenderRetryAttempts
                useWebsocketIfAvailable:YES
                success:^{
                    // The value doesn't matter, we just need any non-NSError value.
                    resolve(@(1));
                }
                failure:^(NSError *error) {
                    @synchronized(sendErrors) {
                        [sendErrors addObject:error];
                    }
                    resolve(error);
                }];
        }];
        [sendPromises addObject:sendPromise];
    }

    // We use PMKJoin(), not PMKWhen(), because we don't want the
    // completion promise to execute until _all_ send promises
    // have either succeeded or failed. PMKWhen() executes as
    // soon as any of its input promises fail.
    AnyPromise *sendCompletionPromise = PMKJoin(sendPromises);
    sendCompletionPromise.then(^(id value) {
        successHandler();
    });
    sendCompletionPromise.catch(^(id failure) {
        NSError *firstRetryableError = nil;
        NSError *firstNonRetryableError = nil;

        NSArray<NSError *> *sendErrorsCopy;
        @synchronized(sendErrors) {
            sendErrorsCopy = [sendErrors copy];
        }

        for (NSError *error in sendErrorsCopy) {
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
    });
    [sendCompletionPromise retainUntilComplete];
}

- (void)unregisteredRecipient:(SignalRecipient *)recipient
                      message:(TSOutgoingMessage *)message
                       thread:(TSThread *)thread
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        if (thread.isGroupThread) {
            // Mark as "skipped" group members who no longer have signal accounts.
            [message updateWithSkippedRecipient:recipient.recipientId transaction:transaction];
        }

        if (![SignalRecipient isRegisteredRecipient:recipient.recipientId transaction:transaction]) {
            return;
        }

        [SignalRecipient removeUnregisteredRecipient:recipient.recipientId transaction:transaction];

        [[TSInfoMessage userNotRegisteredMessageInThread:thread recipientId:recipient.recipientId]
            saveWithTransaction:transaction];

        // TODO: Should we deleteAllSessionsForContact here?
        //       If so, we'll need to avoid doing a prekey fetch every
        //       time we try to send a message to an unregistered user.
    }];
}

- (void)sendMessageToService:(TSOutgoingMessage *)message
                   recipient:(SignalRecipient *)recipient
                      thread:(nullable TSThread *)thread
                    attempts:(int)remainingAttemptsParam
     useWebsocketIfAvailable:(BOOL)useWebsocketIfAvailable
                     success:(void (^)(void))successHandler
                     failure:(RetryableFailureHandler)failureHandler
{
    OWSAssertDebug(message);
    OWSAssertDebug(recipient);
    OWSAssertDebug(thread || [message isKindOfClass:[OWSOutgoingSyncMessage class]]);

    OWSLogInfo(@"attempting to send message: %@, timestamp: %llu, recipient: %@",
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
        [TSPreKeyManager
            rotateSignedPreKeyWithSuccess:^{
                OWSLogInfo(@"New prekeys registered with server.");
                NSError *error = OWSErrorMakeMessageSendDisabledDueToPreKeyUpdateFailuresError();
                [error setIsRetryable:YES];
                return failureHandler(error);
            }
            failure:^(NSError *error) {
                OWSLogWarn(@"Failed to update prekeys with the server: %@", error);
                return failureHandler(error);
            }];
    }

    if (remainingAttemptsParam <= 0) {
        // We should always fail with a specific error.
        OWSProdFail([OWSAnalyticsEvents messageSenderErrorGenericSendFailure]);

        NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
        [error setIsRetryable:YES];
        return failureHandler(error);
    }
    int remainingAttempts = remainingAttemptsParam - 1;

    NSArray<NSDictionary *> *deviceMessages;
    @try {
        deviceMessages = [self deviceMessages:message recipient:recipient];
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
            OWSLogWarn(@"Terminal failure to build any device messages. Giving up with exception:%@", exception);
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
        OWSAssertDebug([message isKindOfClass:[OWSOutgoingSyncMessage class]]);
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

        OWSLogInfo(@"mayHaveLinkedDevices: %d, hasDeviceMessages: %d", mayHaveLinkedDevices, hasDeviceMessages);

        if (!mayHaveLinkedDevices && !hasDeviceMessages) {
            OWSLogInfo(@"Ignoring sync message without secondary devices: %@", [message class]);
            OWSAssertDebug([message isKindOfClass:[OWSOutgoingSyncMessage class]]);

            dispatch_async([OWSDispatch sendingQueue], ^{
                // This emulates the completion logic of an actual successful save (see below).
                [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    [message updateWithSkippedRecipient:localNumber transaction:transaction];
                }];
                successHandler();
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
        OWSAssertDebug(deviceMessages.count > 0);
    }

    if (deviceMessages.count == 0) {
        // This might happen:
        //
        // * The first (after upgrading?) time we send a sync message to our linked devices.
        // * After unlinking all linked devices.
        // * After trying and failing to link a device.
        // * The first time we send a message to a user, if they don't have their
        //   default device.  For example, if they have unregistered
        //   their primary but still have a linked device. Or later, when they re-register.
        //
        // When we're not sure if we have linked devices, we need to try
        // to send self-sync messages even if they have no device messages
        // so that we can learn from the service whether or not there are
        // linked devices that we don't know about.
        OWSLogWarn(@"Sending a message with no device messages.");
    }

    TSRequest *request = [OWSRequestFactory submitMessageRequestWithRecipient:recipient.uniqueId
                                                                     messages:deviceMessages
                                                                    timeStamp:message.timestamp];
    if (useWebsocketIfAvailable && TSSocketManager.canMakeRequests) {
        [TSSocketManager.sharedManager makeRequest:request
            success:^(id _Nullable responseObject) {
                [self messageSendDidSucceed:message
                                  recipient:recipient
                              isLocalNumber:isLocalNumber
                             deviceMessages:deviceMessages
                                    success:successHandler];
            }
            failure:^(NSInteger statusCode, NSData *_Nullable responseData, NSError *error) {
                dispatch_async([OWSDispatch sendingQueue], ^{
                    OWSLogDebug(@"falling back to REST since first attempt failed.");

                    // Websockets can fail in different ways, so we don't decrement remainingAttempts for websocket
                    // failure. Instead we fall back to REST, which will decrement retries. e.g. after linking a new
                    // device, sync messages will fail until the websocket re-opens.
                    [self sendMessageToService:message
                                      recipient:recipient
                                         thread:thread
                                       attempts:remainingAttemptsParam
                        useWebsocketIfAvailable:NO
                                        success:successHandler
                                        failure:failureHandler];
                });
            }];
    } else {
        [self.networkManager makeRequest:request
            success:^(NSURLSessionDataTask *task, id responseObject) {
                [self messageSendDidSucceed:message
                                  recipient:recipient
                              isLocalNumber:isLocalNumber
                             deviceMessages:deviceMessages
                                    success:successHandler];
            }
            failure:^(NSURLSessionDataTask *task, NSError *error) {
                NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
                NSInteger statusCode = response.statusCode;
                NSData *_Nullable responseData = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];

                [self messageSendDidFail:message
                               recipient:recipient
                                  thread:thread
                           isLocalNumber:isLocalNumber
                          deviceMessages:deviceMessages
                       remainingAttempts:remainingAttempts
                              statusCode:statusCode
                                   error:error
                            responseData:responseData
                                 success:successHandler
                                 failure:failureHandler];
            }];
    }
}

- (void)messageSendDidSucceed:(TSOutgoingMessage *)message
                    recipient:(SignalRecipient *)recipient
                isLocalNumber:(BOOL)isLocalNumber
               deviceMessages:(NSArray<NSDictionary *> *)deviceMessages
                      success:(void (^)(void))successHandler
{
    OWSAssertDebug(message);
    OWSAssertDebug(recipient);
    OWSAssertDebug(deviceMessages);
    OWSAssertDebug(successHandler);

    OWSLogInfo(@"Message send succeeded.");

    if (isLocalNumber && deviceMessages.count == 0) {
        OWSLogInfo(@"Sent a message with no device messages; clearing 'mayHaveLinkedDevices'.");
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
            [message updateWithSentRecipient:recipient.uniqueId transaction:transaction];

            // If we've just delivered a message to a user, we know they
            // have a valid Signal account.
            [SignalRecipient markRecipientAsRegisteredAndGet:recipient.recipientId transaction:transaction];
        }];

        [self handleMessageSentLocally:message];
        successHandler();
    });
}

- (void)messageSendDidFail:(TSOutgoingMessage *)message
                 recipient:(SignalRecipient *)recipient
                    thread:(nullable TSThread *)thread
             isLocalNumber:(BOOL)isLocalNumber
            deviceMessages:(NSArray<NSDictionary *> *)deviceMessages
         remainingAttempts:(int)remainingAttempts
                statusCode:(NSInteger)statusCode
                     error:(NSError *)responseError
              responseData:(nullable NSData *)responseData
                   success:(void (^)(void))successHandler
                   failure:(RetryableFailureHandler)failureHandler
{
    OWSAssertDebug(message);
    OWSAssertDebug(recipient);
    OWSAssertDebug(thread || [message isKindOfClass:[OWSOutgoingSyncMessage class]]);
    OWSAssertDebug(deviceMessages);
    OWSAssertDebug(responseError);
    OWSAssertDebug(successHandler);
    OWSAssertDebug(failureHandler);

    OWSLogInfo(@"sending to recipient: %@, failed with error.", recipient.uniqueId);

    void (^retrySend)(void) = ^void() {
        if (remainingAttempts <= 0) {
            // Since we've already repeatedly failed to send to the messaging API,
            // it's unlikely that repeating the whole process will succeed.
            [responseError setIsRetryable:NO];
            return failureHandler(responseError);
        }

        dispatch_async([OWSDispatch sendingQueue], ^{
            OWSLogDebug(@"Retrying: %@", message.debugDescription);
            [self sendMessageToService:message
                              recipient:recipient
                                 thread:thread
                               attempts:remainingAttempts
                useWebsocketIfAvailable:NO
                                success:successHandler
                                failure:failureHandler];
        });
    };

    void (^handle404)(void) = ^{
        OWSLogWarn(@"Unregistered recipient: %@", recipient.uniqueId);

        OWSAssertDebug(thread);

        dispatch_async([OWSDispatch sendingQueue], ^{
            [self unregisteredRecipient:recipient message:message thread:thread];

            NSError *error = OWSErrorMakeNoSuchSignalRecipientError();
            // No need to retry if the recipient is not registered.
            [error setIsRetryable:NO];
            // If one member of a group deletes their account,
            // the group should ignore errors when trying to send
            // messages to this ex-member.
            [error setShouldBeIgnoredForGroups:YES];
            failureHandler(error);
        });
    };

    switch (statusCode) {
        case 401: {
            OWSLogWarn(@"Unable to send due to invalid credentials. Did the user's client get de-authed by "
                       @"registering elsewhere?");
            NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeSignalServiceFailure,
                NSLocalizedString(
                    @"ERROR_DESCRIPTION_SENDING_UNAUTHORIZED", @"Error message when attempting to send message"));
            // No need to retry if we've been de-authed.
            [error setIsRetryable:NO];
            return failureHandler(error);
        }
        case 404: {
            handle404();
            return;
        }
        case 409: {
            // Mismatched devices
            OWSLogWarn(@"Mismatched devices for recipient: %@ (%zd)", recipient.uniqueId, deviceMessages.count);

            NSError *_Nullable error = nil;
            NSDictionary *_Nullable responseJson = nil;
            if (responseData) {
                responseJson = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&error];
            }
            if (error || !responseJson) {
                OWSProdError([OWSAnalyticsEvents messageSenderErrorCouldNotParseMismatchedDevicesJson]);
                [error setIsRetryable:YES];
                return failureHandler(error);
            }

            NSNumber *_Nullable errorCode = responseJson[@"code"];
            if ([@(404) isEqual:errorCode]) {
                // Some 404s are returned as 409.
                handle404();
                return;
            }

            [self handleMismatchedDevicesWithResponseJson:responseJson recipient:recipient completion:retrySend];
            break;
        }
        case 410: {
            // Stale devices
            OWSLogWarn(@"Stale devices for recipient: %@", recipient.uniqueId);

            NSError *_Nullable error = nil;
            NSDictionary *_Nullable responseJson = nil;
            if (responseData) {
                responseJson = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&error];
            }
            if (error || !responseJson) {
                OWSLogWarn(@"Stale devices but server didn't specify devices in response.");
                NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                [error setIsRetryable:YES];
                return failureHandler(error);
            }

            [self handleStaleDevicesWithResponseJson:responseJson recipientId:recipient.uniqueId completion:retrySend];
            break;
        }
        default:
            retrySend();
            break;
    }
}

- (void)handleMismatchedDevicesWithResponseJson:(NSDictionary *)responseJson
                                      recipient:(SignalRecipient *)recipient
                                     completion:(void (^)(void))completionHandler
{
    OWSAssertDebug(responseJson);
    OWSAssertDebug(recipient);
    OWSAssertDebug(completionHandler);

    NSArray *extraDevices = responseJson[@"extraDevices"];
    NSArray *missingDevices = responseJson[@"missingDevices"];

    if (missingDevices.count > 0) {
        NSString *localNumber = [TSAccountManager localNumber];
        if ([localNumber isEqualToString:recipient.uniqueId]) {
            [OWSDeviceManager.sharedManager setMayHaveLinkedDevices];
        }
    }

    [self.dbConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            if (extraDevices.count < 1 && missingDevices.count < 1) {
                OWSProdFail([OWSAnalyticsEvents messageSenderErrorNoMissingOrExtraDevices]);
            }

            if (extraDevices && extraDevices.count > 0) {
                OWSLogInfo(@"removing extra devices: %@", extraDevices);
                for (NSNumber *extraDeviceId in extraDevices) {
                    [self.primaryStorage deleteSessionForContact:recipient.uniqueId
                                                        deviceId:extraDeviceId.intValue
                                                 protocolContext:transaction];
                }

                [recipient removeDevicesFromRecipient:[NSSet setWithArray:extraDevices] transaction:transaction];
            }

            if (missingDevices && missingDevices.count > 0) {
                OWSLogInfo(@"Adding missing devices: %@", missingDevices);
                [recipient addDevicesToRegisteredRecipient:[NSSet setWithArray:missingDevices]
                                              transaction:transaction];
            }

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

- (void)sendSyncTranscriptForMessage:(TSOutgoingMessage *)message
{
    OWSOutgoingSentMessageTranscript *sentMessageTranscript =
        [[OWSOutgoingSentMessageTranscript alloc] initWithOutgoingMessage:message];

    NSString *recipientId = [TSAccountManager localNumber];
    __block SignalRecipient *recipient;
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        recipient = [SignalRecipient markRecipientAsRegisteredAndGet:recipientId transaction:transaction];
    }];

    [self sendMessageToService:sentMessageTranscript
        recipient:recipient
        thread:message.thread
        attempts:OWSMessageSenderRetryAttempts
        useWebsocketIfAvailable:YES
        success:^{
            OWSLogInfo(@"Successfully sent sync transcript.");
        }
        failure:^(NSError *error) {
            // FIXME: We don't yet honor the isRetryable flag here, since sendSyncTranscriptForMessage
            // isn't yet wrapped in our retryable SendMessageOperation. Addressing this would require
            // a refactor to the MessageSender. Note that we *do* however continue to respect the
            // OWSMessageSenderRetryAttempts, which is an "inner" retry loop, encompassing only the
            // messaging API.
            OWSLogInfo(@"Failed to send sync transcript: %@ (isRetryable: %d)", error, [error isRetryable]);
        }];
}

- (NSArray<NSDictionary *> *)deviceMessages:(TSOutgoingMessage *)message recipient:(SignalRecipient *)recipient
{
    OWSAssertDebug(message);
    OWSAssertDebug(recipient);

    NSMutableArray *messagesArray = [NSMutableArray arrayWithCapacity:recipient.devices.count];

    NSData *_Nullable plainText = [message buildPlainTextData:recipient];
    if (!plainText) {
        OWSRaiseException(InvalidMessageException, @"Failed to build message proto");
    }
    OWSLogDebug(@"built message: %@ plainTextData.length: %lu", [message class], (unsigned long)plainText.length);

    for (NSNumber *deviceNumber in recipient.devices) {
        @try {
            __block NSDictionary *messageDict;
            __block NSException *encryptionException;
            [self.dbConnection
                readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    @try {
                        messageDict = [self encryptedMessageWithPlaintext:plainText
                                                                recipient:recipient
                                                                 deviceId:deviceNumber
                                                            keyingStorage:self.primaryStorage
                                                                 isSilent:message.isSilent
                                                              transaction:transaction];
                    } @catch (NSException *exception) {
                        encryptionException = exception;
                    }
                }];

            if (encryptionException) {
                OWSLogInfo(@"Exception during encryption: %@", encryptionException);
                @throw encryptionException;
            }

            if (messageDict) {
                [messagesArray addObject:messageDict];
            } else {
                OWSRaiseException(InvalidMessageException, @"Failed to encrypt message");
            }
        } @catch (NSException *exception) {
            if ([exception.name isEqualToString:OWSMessageSenderInvalidDeviceException]) {
                [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    [recipient removeDevicesFromRecipient:[NSSet setWithObject:deviceNumber] transaction:transaction];
                }];
            } else {
                @throw exception;
            }
        }
    }

    return [messagesArray copy];
}

- (NSDictionary *)encryptedMessageWithPlaintext:(NSData *)plainText
                                      recipient:(SignalRecipient *)recipient
                                       deviceId:(NSNumber *)deviceNumber
                                  keyingStorage:(OWSPrimaryStorage *)storage
                                       isSilent:(BOOL)isSilent
                                    transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(plainText);
    OWSAssertDebug(recipient);
    OWSAssertDebug(deviceNumber);
    OWSAssertDebug(storage);
    OWSAssertDebug(transaction);

    NSString *identifier = recipient.recipientId;
    OWSAssertDebug(identifier.length > 0);

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
                OWSLogError(@"Server replied to PreKeyBundle request with error: %@", error);
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
    if (message.groupMetaMessage == TSGroupMetaMessageDeliver) {
        // TODO: Why is this necessary?
        [message save];
    } else if (message.groupMetaMessage == TSGroupMetaMessageQuit) {
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
- (void)handleStaleDevicesWithResponseJson:(NSDictionary *)responseJson
                               recipientId:(NSString *)identifier
                                completion:(void (^)(void))completionHandler
{
    dispatch_async([OWSDispatch sendingQueue], ^{
        NSArray *devices = responseJson[@"staleDevices"];

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
