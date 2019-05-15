//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageSender.h"
#import "AppContext.h"
#import "NSData+keyVersionByte.h"
#import "NSData+messagePadding.h"
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
#import "TSRequest.h"
#import "TSSocketManager.h"
#import "TSThread.h"
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/CipherMessage.h>
#import <AxolotlKit/PreKeyBundle.h>
#import <AxolotlKit/SessionBuilder.h>
#import <AxolotlKit/SessionCipher.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/SCKExceptionWrapper.h>
#import <SignalCoreKit/Threading.h>
#import <SignalMetadataKit/SignalMetadataKit-Swift.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *NoSessionForTransientMessageException = @"NoSessionForTransientMessageException";

const NSUInteger kOversizeTextMessageSizeThreshold = 2 * 1024;

NSError *SSKEnsureError(NSError *_Nullable error, OWSErrorCode fallbackCode, NSString *fallbackErrorDescription)
{
    if (error) {
        return error;
    }
    OWSCFailDebug(@"Using fallback error.");
    return OWSErrorWithCodeDescription(fallbackCode, fallbackErrorDescription);
}

#pragma mark -

void AssertIsOnSendingQueue()
{
#ifdef DEBUG
    if (@available(iOS 10.0, *)) {
        dispatch_assert_queue([OWSDispatch sendingQueue]);
    } // else, skip assert as it's a development convenience.
#endif
}

#pragma mark -

@implementation OWSOutgoingAttachmentInfo

- (instancetype)initWithDataSource:(DataSource *)dataSource
                       contentType:(NSString *)contentType
                    sourceFilename:(nullable NSString *)sourceFilename
                           caption:(nullable NSString *)caption
                    albumMessageId:(nullable NSString *)albumMessageId
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

    return self;
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
    __block NSError *_Nullable error = [super checkForPreconditionError];
    if (error) {
        return error;
    }

    // Sanity check preconditions
    if (self.message.hasAttachments) {
        [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            for (TSAttachment *attachment in [self.message allAttachmentsWithTransaction:transaction]) {
                if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
                    error = OWSErrorMakeFailedToSendOutgoingMessageError();
                    break;
                }

                TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;
                OWSAssertDebug(attachmentStream);
                OWSAssertDebug(attachmentStream.serverId);
                OWSAssertDebug(attachmentStream.isUploaded);
            }
        }];
    }

    return error;
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
    OWSLogError(@"failed with error: %@", error);
    self.failureHandler(error);
}

@end

#pragma mark -

NSString *const OWSMessageSenderInvalidDeviceException = @"InvalidDeviceException";
NSString *const OWSMessageSenderRateLimitedException = @"RateLimitedException";

@interface OWSMessageSender ()

@property (nonatomic, readonly) OWSPrimaryStorage *primaryStorage;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (atomic, readonly) NSMutableDictionary<NSString *, NSOperationQueue *> *sendingQueueMap;

@end

#pragma mark -

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

#pragma mark - Dependencies

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

- (id<OWSUDManager>)udManager
{
    OWSAssertDebug(SSKEnvironment.shared.udManager);

    return SSKEnvironment.shared.udManager;
}

- (TSAccountManager *)tsAccountManager
{
    return TSAccountManager.sharedInstance;
}

- (OWSIdentityManager *)identityManager
{
    return SSKEnvironment.shared.identityManager;
}

#pragma mark -

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

- (void)sendMessage:(TSOutgoingMessage *)message
            success:(void (^)(void))successHandler
            failure:(void (^)(NSError *error))failureHandler
{
    OWSAssertDebug(message);
    if (message.body.length > 0) {
        OWSAssertDebug([message.body lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= kOversizeTextMessageSizeThreshold);
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray<NSString *> *allAttachmentIds = [NSMutableArray new];

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
            [allAttachmentIds
                addObjectsFromArray:[OutgoingMessagePreparer prepareMessageForSending:message transaction:transaction]];
        }];

        NSOperationQueue *sendingQueue = [self sendingQueueForMessage:message];
        OWSSendMessageOperation *sendMessageOperation =
            [[OWSSendMessageOperation alloc] initWithMessage:message
                                               messageSender:self
                                                dbConnection:self.dbConnection
                                                     success:successHandler
                                                     failure:failureHandler];

        for (NSString *attachmentId in allAttachmentIds) {
            OWSUploadOperation *uploadAttachmentOperation =
                [[OWSUploadOperation alloc] initWithAttachmentId:attachmentId dbConnection:self.dbConnection];
            // TODO: put attachment uploads on a (low priority) concurrent queue
            [sendMessageOperation addDependency:uploadAttachmentOperation];
            [sendingQueue addOperation:uploadAttachmentOperation];
        }

        [sendingQueue addOperation:sendMessageOperation];
    });
}

- (void)sendTemporaryAttachment:(DataSource *)dataSource
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

    [self sendAttachment:dataSource
             contentType:contentType
          sourceFilename:nil
          albumMessageId:nil
               inMessage:message
                 success:successWithDeleteHandler
                 failure:failureWithDeleteHandler];
}

- (void)sendAttachment:(DataSource *)dataSource
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
                                                                                       albumMessageId:albumMessageId];
    [self sendAttachments:@[
        attachmentInfo,
    ]
                inMessage:message
                  success:success
                  failure:failure];
}

- (void)sendAttachments:(NSArray<OWSOutgoingAttachmentInfo *> *)attachmentInfos
              inMessage:(TSOutgoingMessage *)message
                success:(void (^)(void))success
                failure:(void (^)(NSError *error))failure
{
    OWSAssertDebug(attachmentInfos.count > 0);

    [OutgoingMessagePreparer prepareAttachments:attachmentInfos
                                      inMessage:message
                              completionHandler:^(NSError *_Nullable error) {
                                  if (error) {
                                      failure(error);
                                      return;
                                  }
                                  [self sendMessage:message success:success failure:failure];
                              }];
}

- (void)sendMessageToService:(TSOutgoingMessage *)message
                     success:(void (^)(void))success
                     failure:(RetryableFailureHandler)failure
{
    [self.udManager
        ensureSenderCertificateWithSuccess:^(SMKSenderCertificate *senderCertificate) {
            dispatch_async([OWSDispatch sendingQueue], ^{
                [self sendMessageToService:message senderCertificate:senderCertificate success:success failure:failure];
            });
        }
        failure:^(NSError *error) {
            OWSLogError(@"Could not obtain UD sender certificate: %@", error);

            // Proceed using non-UD message sends.
            dispatch_async([OWSDispatch sendingQueue], ^{
                [self sendMessageToService:message senderCertificate:nil success:success failure:failure];
            });
        }];
}

- (nullable NSArray<NSString *> *)unsentRecipientsForMessage:(TSOutgoingMessage *)message
                                                      thread:(nullable TSThread *)thread
                                                       error:(NSError **)errorHandle
{
    OWSAssertDebug(message);
    OWSAssertDebug(errorHandle);

    NSMutableSet<NSString *> *recipientIds = [NSMutableSet new];
    if ([message isKindOfClass:[OWSOutgoingSyncMessage class]]) {
        [recipientIds addObject:self.tsAccountManager.localNumber];
    } else if (thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;

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

        [recipientIds addObjectsFromArray:message.sendingRecipientIds];
        // Only send to members in the latest known group member list.
        [recipientIds intersectSet:[NSSet setWithArray:groupThread.groupModel.groupMemberIds]];

        if ([recipientIds containsObject:self.tsAccountManager.localNumber]) {
            OWSFailDebug(@"Message send recipients should not include self.");
        }
    } else if ([thread isKindOfClass:[TSContactThread class]]) {
        NSString *recipientContactId = ((TSContactThread *)thread).contactIdentifier;

        // Treat 1:1 sends to blocked contacts as failures.
        // If we block a user, don't send 1:1 messages to them. The UI
        // should prevent this from occurring, but in some edge cases
        // you might, for example, have a pending outgoing message when
        // you block them.
        OWSAssertDebug(recipientContactId.length > 0);
        if ([self.blockingManager isRecipientIdBlocked:recipientContactId]) {
            OWSLogInfo(@"skipping 1:1 send to blocked contact: %@", recipientContactId);
            NSError *error = OWSErrorMakeMessageSendFailedDueToBlockListError();
            [error setIsRetryable:NO];
            *errorHandle = error;
            return nil;
        }

        [recipientIds addObject:recipientContactId];

        if ([recipientIds containsObject:self.tsAccountManager.localNumber]) {
            OWSFailDebug(@"Message send recipients should not include self.");
        }
    } else {
        // Neither a group nor contact thread? This should never happen.
        OWSFailDebug(@"Unknown message type: %@", [message class]);
        NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
        [error setIsRetryable:NO];
        *errorHandle = error;
        return nil;
    }

    [recipientIds minusSet:[NSSet setWithArray:self.blockingManager.blockedPhoneNumbers]];
    return recipientIds.allObjects;
}

- (NSArray<SignalRecipient *> *)recipientsForRecipientIds:(NSArray<NSString *> *)recipientIds
{
    OWSAssertDebug(recipientIds.count > 0);

    NSMutableArray<SignalRecipient *> *recipients = [NSMutableArray new];
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        for (NSString *recipientId in recipientIds) {
            SignalRecipient *recipient =
                [SignalRecipient getOrBuildUnsavedRecipientForRecipientId:recipientId transaction:transaction];
            [recipients addObject:recipient];
        }
    }];
    return [recipients copy];
}

- (AnyPromise *)sendPromiseForRecipients:(NSArray<SignalRecipient *> *)recipients
                                 message:(TSOutgoingMessage *)message
                                  thread:(nullable TSThread *)thread
                       senderCertificate:(nullable SMKSenderCertificate *)senderCertificate
                              sendErrors:(NSMutableArray<NSError *> *)sendErrors
{
    OWSAssertDebug(recipients.count > 0);
    OWSAssertDebug(message);
    OWSAssertDebug(sendErrors);

    NSMutableArray<AnyPromise *> *sendPromises = [NSMutableArray array];

    for (SignalRecipient *recipient in recipients) {
        // Use chained promises to make the code more readable.
        AnyPromise *sendPromise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
            NSString *localNumber = self.tsAccountManager.localNumber;
            OWSUDAccess *_Nullable theirUDAccess;
            if (senderCertificate != nil && ![recipient.recipientId isEqualToString:localNumber]) {
                theirUDAccess = [self.udManager udAccessForRecipientId:recipient.recipientId requireSyncAccess:YES];
            }

            OWSMessageSend *messageSend = [[OWSMessageSend alloc] initWithMessage:message
                thread:thread
                recipient:recipient
                senderCertificate:senderCertificate
                udAccess:theirUDAccess
                localNumber:self.tsAccountManager.localNumber
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
            [self sendMessageToRecipient:messageSend];
        }];
        [sendPromises addObject:sendPromise];
    }

    // We use PMKJoin(), not PMKWhen(), because we don't want the
    // completion promise to execute until _all_ send promises
    // have either succeeded or failed. PMKWhen() executes as
    // soon as any of its input promises fail.
    return PMKJoin(sendPromises);
}

- (void)sendMessageToService:(TSOutgoingMessage *)message
           senderCertificate:(nullable SMKSenderCertificate *)senderCertificate
                     success:(void (^)(void))successHandlerParam
                     failure:(RetryableFailureHandler)failureHandlerParam
{
    AssertIsOnSendingQueue();

    void (^successHandler)(void) = ^() {
        dispatch_async([OWSDispatch sendingQueue], ^{
            [self handleMessageSentLocally:message
                success:^{
                    successHandlerParam();
                }
                failure:^(NSError *error) {
                    OWSLogError(@"Error sending sync message for message: %@ timestamp: %llu",
                        message.class,
                        message.timestamp);

                    failureHandlerParam(error);
                }];
        });
    };
    void (^failureHandler)(NSError *) = ^(NSError *error) {
        if (message.wasSentToAnyRecipient) {
            dispatch_async([OWSDispatch sendingQueue], ^{
                [self handleMessageSentLocally:message
                    success:^{
                        failureHandlerParam(error);
                    }
                    failure:^(NSError *syncError) {
                        OWSLogError(@"Error sending sync message for message: %@ timestamp: %llu, %@",
                            message.class,
                            message.timestamp,
                            syncError);

                        // Discard the "sync message" error in favor of the
                        // original error.
                        failureHandlerParam(error);
                    }];
            });
            return;
        }
        failureHandlerParam(error);
    };

    TSThread *_Nullable thread = message.thread;

    BOOL isSyncMessage = [message isKindOfClass:[OWSOutgoingSyncMessage class]];
    if (!thread && !isSyncMessage) {
        OWSFailDebug(@"Missing thread for non-sync message.");

        // This thread has been deleted since the message was enqueued.
        NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeMessageSendNoValidRecipients,
            NSLocalizedString(@"ERROR_DESCRIPTION_NO_VALID_RECIPIENTS",
                @"Error indicating that an outgoing message had no valid recipients."));
        [error setIsRetryable:NO];
        return failureHandler(error);
    }

    // In the "self-send" special case, we ony need to send a sync message with a delivery receipt.
    if ([thread isKindOfClass:[TSContactThread class]] &&
        [((TSContactThread *)thread).contactIdentifier isEqualToString:self.tsAccountManager.localNumber]) {
        // Send to self.
        OWSAssertDebug(message.recipientIds.count == 1);
        // Don't mark self-sent messages as read (or sent) until the sync transcript is sent.
        successHandler();
        return;
    }

    if (thread.isGroupThread) {
        [self saveInfoMessageForGroupMessage:message inThread:thread];
    }

    NSError *error;
    NSArray<NSString *> *_Nullable recipientIds = [self unsentRecipientsForMessage:message thread:thread error:&error];
    if (error || !recipientIds) {
        error = SSKEnsureError(
            error, OWSErrorCodeMessageSendNoValidRecipients, @"Could not build recipients list for message.");
        [error setIsRetryable:NO];
        return failureHandler(error);
    }

    // Mark skipped recipients as such.  We skip because:
    //
    // * Recipient is no longer in the group.
    // * Recipient is blocked.
    //
    // Elsewhere, we skip recipient if their Signal account has been deactivated.
    NSMutableSet<NSString *> *obsoleteRecipientIds = [NSMutableSet setWithArray:message.sendingRecipientIds];
    [obsoleteRecipientIds minusSet:[NSSet setWithArray:recipientIds]];
    if (obsoleteRecipientIds.count > 0) {
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            for (NSString *recipientId in obsoleteRecipientIds) {
                // Mark this recipient as "skipped".
                [message updateWithSkippedRecipient:recipientId transaction:transaction];
            }
        }];
    }

    if (recipientIds.count < 1) {
        // All recipients are already sent or can be skipped.
        successHandler();
        return;
    }

    NSArray<SignalRecipient *> *recipients = [self recipientsForRecipientIds:recipientIds];

    BOOL isGroupSend = (thread && thread.isGroupThread);
    NSMutableArray<NSError *> *sendErrors = [NSMutableArray array];
    AnyPromise *sendPromise = [self sendPromiseForRecipients:recipients
                                                     message:message
                                                      thread:thread
                                           senderCertificate:senderCertificate
                                                  sendErrors:sendErrors]
                                  .then(^(id value) {
                                      successHandler();
                                  });
    sendPromise.catch(^(id failure) {
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
            if (isGroupSend && [error shouldBeIgnoredForGroups]) {
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
    [sendPromise retainUntilComplete];
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

        [SignalRecipient markRecipientAsUnregistered:recipient.recipientId transaction:transaction];

        [[TSInfoMessage userNotRegisteredMessageInThread:thread recipientId:recipient.recipientId]
            saveWithTransaction:transaction];

        // TODO: Should we deleteAllSessionsForContact here?
        //       If so, we'll need to avoid doing a prekey fetch every
        //       time we try to send a message to an unregistered user.
    }];
}

- (nullable NSArray<NSDictionary *> *)deviceMessagesForMessageSend:(OWSMessageSend *)messageSend
                                                             error:(NSError **)errorHandle
{
    OWSAssertDebug(messageSend);
    OWSAssertDebug(errorHandle);
    AssertIsOnSendingQueue();

    SignalRecipient *recipient = messageSend.recipient;

    NSArray<NSDictionary *> *deviceMessages;
    @try {
        deviceMessages = [self throws_deviceMessagesForMessageSend:messageSend];
    } @catch (NSException *exception) {
        if ([exception.name isEqualToString:NoSessionForTransientMessageException]) {
            // When users re-register, we don't want transient messages (like typing
            // indicators) to cause users to hit the prekey fetch rate limit.  So
            // we silently discard these message if there is no pre-existing session
            // for the recipient.
            NSError *error = OWSErrorWithCodeDescription(
                OWSErrorCodeNoSessionForTransientMessage, @"No session for transient message.");
            [error setIsRetryable:NO];
            [error setIsFatal:YES];
            *errorHandle = error;
            return nil;
        } else if ([exception.name isEqualToString:UntrustedIdentityKeyException]) {
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
            *errorHandle = error;

            PreKeyBundle *_Nullable newKeyBundle = exception.userInfo[TSInvalidPreKeyBundleKey];
            if (newKeyBundle == nil) {
                OWSProdFail([OWSAnalyticsEvents messageSenderErrorMissingNewPreKeyBundle]);
                return nil;
            }

            if (![newKeyBundle isKindOfClass:[PreKeyBundle class]]) {
                OWSProdFail([OWSAnalyticsEvents messageSenderErrorUnexpectedKeyBundle]);
                return nil;
            }

            NSData *newIdentityKeyWithVersion = newKeyBundle.identityKey;

            if (![newIdentityKeyWithVersion isKindOfClass:[NSData class]]) {
                OWSProdFail([OWSAnalyticsEvents messageSenderErrorInvalidIdentityKeyType]);
                return nil;
            }

            // TODO migrate to storing the full 33 byte representation of the identity key.
            if (newIdentityKeyWithVersion.length != kIdentityKeyLength) {
                OWSProdFail([OWSAnalyticsEvents messageSenderErrorInvalidIdentityKeyLength]);
                return nil;
            }

            NSData *newIdentityKey = [newIdentityKeyWithVersion throws_removeKeyType];
            [self.identityManager saveRemoteIdentity:newIdentityKey recipientId:recipient.recipientId];

            return nil;
        }

        if ([exception.name isEqualToString:OWSMessageSenderRateLimitedException]) {
            NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeSignalServiceRateLimited,
                NSLocalizedString(@"FAILED_SENDING_BECAUSE_RATE_LIMIT",
                    @"action sheet header when re-sending message which failed because of too many attempts"));
            // We're already rate-limited. No need to exacerbate the problem.
            [error setIsRetryable:NO];
            // Avoid exacerbating the rate limiting.
            [error setIsFatal:YES];
            *errorHandle = error;
            return nil;
        }

        OWSLogWarn(@"Could not build device messages: %@", exception);
        NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
        [error setIsRetryable:YES];
        *errorHandle = error;
        return nil;
    }

    return deviceMessages;
}

- (void)sendMessageToRecipient:(OWSMessageSend *)messageSend
{
    OWSAssertDebug(messageSend);
    OWSAssertDebug(messageSend.thread || [messageSend.message isKindOfClass:[OWSOutgoingSyncMessage class]]);

    TSOutgoingMessage *message = messageSend.message;
    SignalRecipient *recipient = messageSend.recipient;

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
                return messageSend.failure(error);
            }
            failure:^(NSError *error) {
                OWSLogWarn(@"Failed to update prekeys with the server: %@", error);
                return messageSend.failure(error);
            }];
    }

    if (messageSend.remainingAttempts <= 0) {
        // We should always fail with a specific error.
        OWSProdFail([OWSAnalyticsEvents messageSenderErrorGenericSendFailure]);

        NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
        [error setIsRetryable:YES];
        return messageSend.failure(error);
    }

    // Consume an attempt.
    messageSend.remainingAttempts = messageSend.remainingAttempts - 1;

    // We need to disable UD for sync messages before we build the device messages,
    // since we don't want to build a device message for the local device in the
    // non-UD auth case.
    if ([message isKindOfClass:[OWSOutgoingSyncMessage class]]
        && ![message isKindOfClass:[OWSOutgoingSentMessageTranscript class]]) {
        [messageSend disableUD];
    }

    NSError *deviceMessagesError;
    NSArray<NSDictionary *> *_Nullable deviceMessages =
        [self deviceMessagesForMessageSend:messageSend error:&deviceMessagesError];
    if (deviceMessagesError || !deviceMessages) {
        OWSAssertDebug(deviceMessagesError);
        return messageSend.failure(deviceMessagesError);
    }

    if (messageSend.isLocalNumber) {
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
        //
        // NOTE: Sync messages sent via UD include the local device.

        BOOL mayHaveLinkedDevices = [OWSDeviceManager.sharedManager mayHaveLinkedDevices:self.dbConnection];

        BOOL hasDeviceMessages = NO;
        for (NSDictionary<NSString *, id> *deviceMessage in deviceMessages) {
            NSString *_Nullable destination = deviceMessage[@"destination"];
            if (!destination) {
                OWSFailDebug(@"Sync device message missing destination: %@", deviceMessage);
                continue;
            }
            if (![destination isEqualToString:messageSend.localNumber]) {
                OWSFailDebug(@"Sync device message has invalid destination: %@", deviceMessage);
                continue;
            }
            NSNumber *_Nullable destinationDeviceId = deviceMessage[@"destinationDeviceId"];
            if (!destinationDeviceId) {
                OWSFailDebug(@"Sync device message missing destination device id: %@", deviceMessage);
                continue;
            }
            if (destinationDeviceId.intValue != OWSDevicePrimaryDeviceId) {
                hasDeviceMessages = YES;
                break;
            }
        }

        OWSLogInfo(@"mayHaveLinkedDevices: %d, hasDeviceMessages: %d", mayHaveLinkedDevices, hasDeviceMessages);

        if (!mayHaveLinkedDevices && !hasDeviceMessages) {
            OWSLogInfo(@"Ignoring sync message without secondary devices: %@", [message class]);
            OWSAssertDebug([message isKindOfClass:[OWSOutgoingSyncMessage class]]);

            dispatch_async([OWSDispatch sendingQueue], ^{
                // This emulates the completion logic of an actual successful send (see below).
                [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    [message updateWithSkippedRecipient:messageSend.localNumber transaction:transaction];
                }];
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

    for (NSDictionary *deviceMessage in deviceMessages) {
        NSNumber *_Nullable messageType = deviceMessage[@"type"];
        OWSAssertDebug(messageType);
        BOOL hasValidMessageType;
        if (messageSend.isUDSend) {
            hasValidMessageType = [messageType isEqualToNumber:@(TSUnidentifiedSenderMessageType)];
        } else {
            hasValidMessageType = ([messageType isEqualToNumber:@(TSEncryptedWhisperMessageType)] ||
                [messageType isEqualToNumber:@(TSPreKeyWhisperMessageType)]);
        }

        if (!hasValidMessageType) {
            OWSFailDebug(@"Invalid message type: %@", messageType);
            NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
            [error setIsRetryable:NO];
            return messageSend.failure(error);
        }
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

    OWSRequestMaker *requestMaker = [[OWSRequestMaker alloc] initWithLabel:@"Message Send"
        requestFactoryBlock:^(SMKUDAccessKey *_Nullable udAccessKey) {
            return [OWSRequestFactory submitMessageRequestWithRecipient:recipient.recipientId
                                                               messages:deviceMessages
                                                              timeStamp:message.timestamp
                                                            udAccessKey:udAccessKey];
        }
        udAuthFailureBlock:^{
            // Note the UD auth failure so subsequent retries
            // to this recipient also use basic auth.
            [messageSend setHasUDAuthFailed];
        }
        websocketFailureBlock:^{
            // Note the websocket failure so subsequent retries
            // to this recipient also use REST.
            messageSend.hasWebsocketSendFailed = YES;
        }
        recipientId:recipient.recipientId
        udAccess:messageSend.udAccess
        canFailoverUDAuth:NO];
    [[requestMaker makeRequestObjc]
            .then(^(OWSRequestMakerResult *result) {
                dispatch_async([OWSDispatch sendingQueue], ^{
                    [self messageSendDidSucceed:messageSend
                                 deviceMessages:deviceMessages
                                    wasSentByUD:result.wasSentByUD
                             wasSentByWebsocket:result.wasSentByWebsocket];
                });
            })
            .catch(^(NSError *error) {
                dispatch_async([OWSDispatch sendingQueue], ^{
                    NSUInteger statusCode = 0;
                    NSData *_Nullable responseData = nil;
                    if ([error.domain isEqualToString:@"SignalServiceKit.RequestMakerUDAuthError"]) {
                        // Try again.
                        OWSLogInfo(@"UD request auth failed; failing over to non-UD request.");
                        [error setIsRetryable:YES];
                    } else if ([error.domain isEqualToString:TSNetworkManagerErrorDomain]) {
                        statusCode = error.code;

                        NSError *_Nullable underlyingError = error.userInfo[NSUnderlyingErrorKey];
                        if (underlyingError) {
                            responseData
                                = underlyingError.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
                        } else {
                            OWSFailDebug(@"Missing underlying error: %@", error);
                        }
                    } else {
                        OWSFailDebug(@"Unexpected error: %@", error);
                    }

                    [self messageSendDidFail:messageSend
                              deviceMessages:deviceMessages
                                  statusCode:statusCode
                                       error:error
                                responseData:responseData];
                });
            }) retainUntilComplete];
}

- (void)messageSendDidSucceed:(OWSMessageSend *)messageSend
               deviceMessages:(NSArray<NSDictionary *> *)deviceMessages
                  wasSentByUD:(BOOL)wasSentByUD
           wasSentByWebsocket:(BOOL)wasSentByWebsocket
{
    OWSAssertDebug(messageSend);
    OWSAssertDebug(deviceMessages);

    SignalRecipient *recipient = messageSend.recipient;

    OWSLogInfo(@"successfully sent message: %@ timestamp: %llu, wasSentByUD: %d",
               messageSend.message.class, messageSend.message.timestamp, wasSentByUD);

    if (messageSend.isLocalNumber && deviceMessages.count == 0) {
        OWSLogInfo(@"Sent a message with no device messages; clearing 'mayHaveLinkedDevices'.");
        // In order to avoid skipping necessary sync messages, the default value
        // for mayHaveLinkedDevices is YES.  Once we've successfully sent a
        // sync message with no device messages (e.g. the service has confirmed
        // that we have no linked devices), we can set mayHaveLinkedDevices to NO
        // to avoid unnecessary message sends for sync messages until we learn
        // of a linked device (e.g. through the device linking UI or by receiving
        // a sync message, etc.).
        [OWSDeviceManager.sharedManager clearMayHaveLinkedDevices];
    }

    dispatch_async([OWSDispatch sendingQueue], ^{
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [messageSend.message updateWithSentRecipient:messageSend.recipient.uniqueId
                                             wasSentByUD:wasSentByUD
                                             transaction:transaction];

            // If we've just delivered a message to a user, we know they
            // have a valid Signal account.
            [SignalRecipient markRecipientAsRegisteredAndGet:recipient.recipientId transaction:transaction];
        }];

        messageSend.success();
    });
}

- (void)messageSendDidFail:(OWSMessageSend *)messageSend
            deviceMessages:(NSArray<NSDictionary *> *)deviceMessages
                statusCode:(NSInteger)statusCode
                     error:(NSError *)responseError
              responseData:(nullable NSData *)responseData
{
    OWSAssertDebug(messageSend);
    OWSAssertDebug(messageSend.thread || [messageSend.message isKindOfClass:[OWSOutgoingSyncMessage class]]);
    OWSAssertDebug(deviceMessages);
    OWSAssertDebug(responseError);

    TSOutgoingMessage *message = messageSend.message;
    SignalRecipient *recipient = messageSend.recipient;

    OWSLogInfo(@"failed to send message: %@, timestamp: %llu, to recipient: %@",
        message.class,
        message.timestamp,
        recipient.uniqueId);

    void (^retrySend)(void) = ^void() {
        if (messageSend.remainingAttempts <= 0) {
            return messageSend.failure(responseError);
        }

        dispatch_async([OWSDispatch sendingQueue], ^{
            OWSLogDebug(@"Retrying: %@", message.debugDescription);
            [self sendMessageToRecipient:messageSend];
        });
    };

    void (^handle404)(void) = ^{
        OWSLogWarn(@"Unregistered recipient: %@", recipient.uniqueId);

        dispatch_async([OWSDispatch sendingQueue], ^{
            if (![messageSend.message isKindOfClass:[OWSOutgoingSyncMessage class]]) {
                TSThread *_Nullable thread = messageSend.thread;
                OWSAssertDebug(thread);
                [self unregisteredRecipient:recipient message:message thread:thread];
            }

            NSError *error = OWSErrorMakeNoSuchSignalRecipientError();
            // No need to retry if the recipient is not registered.
            [error setIsRetryable:NO];
            // If one member of a group deletes their account,
            // the group should ignore errors when trying to send
            // messages to this ex-member.
            [error setShouldBeIgnoredForGroups:YES];
            messageSend.failure(error);
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
            return messageSend.failure(error);
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
                return messageSend.failure(error);
            }

            NSNumber *_Nullable errorCode = responseJson[@"code"];
            if ([@(404) isEqual:errorCode]) {
                // Some 404s are returned as 409.
                handle404();
                return;
            }

            [self handleMismatchedDevicesWithResponseJson:responseJson recipient:recipient completion:retrySend];

            if (messageSend.isLocalNumber) {
                // Don't use websocket; it may have obsolete cached state.
                [messageSend setHasWebsocketSendFailed:YES];
            }

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
                return messageSend.failure(error);
            }

            [self handleStaleDevicesWithResponseJson:responseJson recipientId:recipient.uniqueId completion:retrySend];

            if (messageSend.isLocalNumber) {
                // Don't use websocket; it may have obsolete cached state.
                [messageSend setHasWebsocketSendFailed:YES];
            }

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
        NSString *localNumber = self.tsAccountManager.localNumber;
        if ([localNumber isEqualToString:recipient.uniqueId]) {
            [OWSDeviceManager.sharedManager setMayHaveLinkedDevices];
        }
    }

    [self.dbConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            if (extraDevices.count < 1 && missingDevices.count < 1) {
                OWSProdFail([OWSAnalyticsEvents messageSenderErrorNoMissingOrExtraDevices]);
            }

            [recipient updateRegisteredRecipientWithDevicesToAdd:missingDevices
                                                 devicesToRemove:extraDevices
                                                     transaction:transaction];

            if (extraDevices && extraDevices.count > 0) {
                OWSLogInfo(@"Deleting sessions for extra devices: %@", extraDevices);
                for (NSNumber *extraDeviceId in extraDevices) {
                    [self.primaryStorage deleteSessionForContact:recipient.uniqueId
                                                        deviceId:extraDeviceId.intValue
                                                     transaction:transaction];
                }
            }

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                completionHandler();
            });
        }];
}

- (void)handleMessageSentLocally:(TSOutgoingMessage *)message
                         success:(void (^)(void))successParam
                         failure:(RetryableFailureHandler)failure
{
    dispatch_block_t success = ^{
        TSThread *_Nullable thread = message.thread;
        if (thread && [thread isKindOfClass:[TSContactThread class]] &&
            [thread.contactIdentifier isEqualToString:self.tsAccountManager.localNumber]) {
            OWSAssertDebug(message.recipientIds.count == 1);
            // Don't mark self-sent messages as read (or sent) until the sync transcript is sent.
            [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                for (NSString *recipientId in message.sendingRecipientIds) {
                    [message updateWithReadRecipientId:recipientId
                                         readTimestamp:message.timestamp
                                           transaction:transaction];
                }
            }];
        }

        successParam();
    };

    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [[OWSDisappearingMessagesJob sharedJob] startAnyExpirationForMessage:message
                                                         expirationStartedAt:[NSDate ows_millisecondTimeStamp]
                                                                 transaction:transaction];
    }];

    if (!message.shouldSyncTranscript) {
        return success();
    }

    BOOL shouldSendTranscript = (AreRecipientUpdatesEnabled() || !message.hasSyncedTranscript);
    if (!shouldSendTranscript) {
        return success();
    }

    BOOL isRecipientUpdate = message.hasSyncedTranscript;
    [self
        sendSyncTranscriptForMessage:message
                   isRecipientUpdate:isRecipientUpdate
                             success:^{
                                 [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                     [message updateWithHasSyncedTranscript:YES transaction:transaction];
                                 }];

                                 success();
                             }
                             failure:failure];
}

- (void)sendSyncTranscriptForMessage:(TSOutgoingMessage *)message
                   isRecipientUpdate:(BOOL)isRecipientUpdate
                             success:(void (^)(void))success
                             failure:(RetryableFailureHandler)failure
{
    OWSOutgoingSentMessageTranscript *sentMessageTranscript =
        [[OWSOutgoingSentMessageTranscript alloc] initWithOutgoingMessage:message isRecipientUpdate:isRecipientUpdate];

    NSString *recipientId = self.tsAccountManager.localNumber;
    __block SignalRecipient *recipient;
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        recipient = [SignalRecipient markRecipientAsRegisteredAndGet:recipientId transaction:transaction];
    }];

    OWSMessageSend *messageSend = [[OWSMessageSend alloc] initWithMessage:sentMessageTranscript
        thread:message.thread
        recipient:recipient
        senderCertificate:nil
        udAccess:nil
        localNumber:self.tsAccountManager.localNumber
        success:^{
            OWSLogInfo(@"Successfully sent sync transcript.");

            success();
        }
        failure:^(NSError *error) {
            OWSLogInfo(@"Failed to send sync transcript: %@ (isRetryable: %d)", error, [error isRetryable]);

            failure(error);
        }];
    [self sendMessageToRecipient:messageSend];
}

- (NSArray<NSDictionary *> *)throws_deviceMessagesForMessageSend:(OWSMessageSend *)messageSend
{
    OWSAssertDebug(messageSend.message);
    OWSAssertDebug(messageSend.recipient);

    SignalRecipient *recipient = messageSend.recipient;

    NSMutableArray *messagesArray = [NSMutableArray arrayWithCapacity:recipient.devices.count];

    NSData *_Nullable plainText = [messageSend.message buildPlainTextData:messageSend.recipient];
    if (!plainText) {
        OWSRaiseException(InvalidMessageException, @"Failed to build message proto");
    }
    OWSLogDebug(
        @"built message: %@ plainTextData.length: %lu", [messageSend.message class], (unsigned long)plainText.length);

    OWSLogVerbose(@"building device messages for: %@ %@ (isLocalNumber: %d, isUDSend: %d)",
        recipient.recipientId,
        recipient.devices,
        messageSend.isLocalNumber,
        messageSend.isUDSend);

    NSMutableArray<NSNumber *> *deviceIds = [recipient.devices mutableCopy];
    OWSAssertDebug(deviceIds);

    if (messageSend.isLocalNumber) {
        [deviceIds removeObject:@(OWSDevicePrimaryDeviceId)];
    }

    for (NSNumber *deviceId in deviceIds) {
        @try {
            // This may involve blocking network requests, so we do it _before_
            // we open a transaction.
            [self throws_ensureRecipientHasSessionForMessageSend:messageSend deviceId:deviceId];

            __block NSDictionary *_Nullable messageDict;
            __block NSException *encryptionException;
            [self.dbConnection
                readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    @try {
                        messageDict = [self throws_encryptedMessageForMessageSend:messageSend
                                                                         deviceId:deviceId
                                                                        plainText:plainText
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
                    [recipient updateRegisteredRecipientWithDevicesToAdd:nil
                                                         devicesToRemove:@[ deviceId ]
                                                             transaction:transaction];
                }];
            } else {
                @throw exception;
            }
        }
    }

    return [messagesArray copy];
}

- (void)throws_ensureRecipientHasSessionForMessageSend:(OWSMessageSend *)messageSend deviceId:(NSNumber *)deviceId
{
    OWSAssertDebug(messageSend);
    OWSAssertDebug(deviceId);

    OWSPrimaryStorage *storage = self.primaryStorage;
    SignalRecipient *recipient = messageSend.recipient;
    NSString *recipientId = recipient.recipientId;
    OWSAssertDebug(recipientId.length > 0);

    __block BOOL hasSession;
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        hasSession = [storage containsSession:recipientId deviceId:[deviceId intValue] transaction:transaction];
    }];
    if (hasSession) {
        return;
    }
    // Discard "typing indicator" messages if there is no existing session with the user.
    BOOL canSafelyBeDiscarded = messageSend.message.isOnline;
    if (canSafelyBeDiscarded) {
        OWSRaiseException(NoSessionForTransientMessageException, @"No session for transient message.");
    }

    __block dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block PreKeyBundle *_Nullable bundle;
    __block NSException *_Nullable exception;
    [self makePrekeyRequestForMessageSend:messageSend
        deviceId:deviceId
        success:^(PreKeyBundle *_Nullable responseBundle) {
            bundle = responseBundle;
            dispatch_semaphore_signal(sema);
        }
        failure:^(NSUInteger statusCode) {
            if (statusCode == 404) {
                // Can't throw exception from within callback as it's probabably a different thread.
                exception = [NSException exceptionWithName:OWSMessageSenderInvalidDeviceException
                                                    reason:@"Device not registered"
                                                  userInfo:nil];
            } else if (statusCode == 413) {
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
        NSString *missingPrekeyBundleException = @"missingPrekeyBundleException";
        OWSRaiseException(
            missingPrekeyBundleException, @"Can't get a prekey bundle from the server with required information");
    } else {
        SessionBuilder *builder = [[SessionBuilder alloc] initWithSessionStore:storage
                                                                   preKeyStore:storage
                                                             signedPreKeyStore:storage
                                                              identityKeyStore:self.identityManager
                                                                   recipientId:recipientId
                                                                      deviceId:[deviceId intValue]];
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            @try {
                [builder throws_processPrekeyBundle:bundle protocolContext:transaction];
            } @catch (NSException *caughtException) {
                exception = caughtException;
            }
        }];
        if (exception) {
            if ([exception.name isEqualToString:UntrustedIdentityKeyException]) {
                OWSRaiseExceptionWithUserInfo(UntrustedIdentityKeyException,
                    (@{ TSInvalidPreKeyBundleKey : bundle, TSInvalidRecipientKey : recipientId }),
                    @"");
            }
            @throw exception;
        }
    }
}

- (void)makePrekeyRequestForMessageSend:(OWSMessageSend *)messageSend
                               deviceId:(NSNumber *)deviceId
                                success:(void (^)(PreKeyBundle *_Nullable))success
                                failure:(void (^)(NSUInteger))failure {
    OWSAssertDebug(messageSend);
    OWSAssertDebug(deviceId);

    SignalRecipient *recipient = messageSend.recipient;
    NSString *recipientId = recipient.recipientId;
    OWSAssertDebug(recipientId.length > 0);

    OWSRequestMaker *requestMaker = [[OWSRequestMaker alloc] initWithLabel:@"Prekey Fetch"
        requestFactoryBlock:^(SMKUDAccessKey *_Nullable udAccessKey) {
            return [OWSRequestFactory recipientPrekeyRequestWithRecipient:recipientId
                                                                 deviceId:[deviceId stringValue]
                                                              udAccessKey:udAccessKey];
        }
        udAuthFailureBlock:^{
            // Note the UD auth failure so subsequent retries
            // to this recipient also use basic auth.
            [messageSend setHasUDAuthFailed];
        }
        websocketFailureBlock:^{
            // Note the websocket failure so subsequent retries
            // to this recipient also use REST.
            messageSend.hasWebsocketSendFailed = YES;
        }
        recipientId:recipientId
        udAccess:messageSend.udAccess
        canFailoverUDAuth:YES];
    [[requestMaker makeRequestObjc]
            .then(^(OWSRequestMakerResult *result) {
                // We _do not_ want to dispatch to the sendingQueue here; we're
                // using a semaphore on the sendingQueue to block on this request.
                const id responseObject = result.responseObject;
                PreKeyBundle *_Nullable bundle =
                    [PreKeyBundle preKeyBundleFromDictionary:responseObject forDeviceNumber:deviceId];
                success(bundle);
            })
            .catch(^(NSError *error) {
                // We _do not_ want to dispatch to the sendingQueue here; we're
                // using a semaphore on the sendingQueue to block on this request.
                NSUInteger statusCode = 0;
                if ([error.domain isEqualToString:TSNetworkManagerErrorDomain]) {
                    statusCode = error.code;
                } else {
                    OWSFailDebug(@"Unexpected error: %@", error);
                }

                failure(statusCode);
            }) retainUntilComplete];
}

- (nullable NSDictionary *)throws_encryptedMessageForMessageSend:(OWSMessageSend *)messageSend
                                                        deviceId:(NSNumber *)deviceId
                                                       plainText:(NSData *)plainText
                                                     transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(messageSend);
    OWSAssertDebug(deviceId);
    OWSAssertDebug(plainText);
    OWSAssertDebug(transaction);

    OWSPrimaryStorage *storage = self.primaryStorage;
    TSOutgoingMessage *message = messageSend.message;
    SignalRecipient *recipient = messageSend.recipient;
    NSString *recipientId = recipient.recipientId;
    OWSAssertDebug(recipientId.length > 0);

    // This may throw an exception.
    if (![storage containsSession:recipientId deviceId:[deviceId intValue] transaction:transaction]) {
        NSString *missingSessionException = @"missingSessionException";
        OWSRaiseException(missingSessionException,
            @"Unexpectedly missing session for recipient: %@, device: %@",
            recipientId,
            deviceId);
    }

    SessionCipher *cipher = [[SessionCipher alloc] initWithSessionStore:storage
                                                            preKeyStore:storage
                                                      signedPreKeyStore:storage
                                                       identityKeyStore:self.identityManager
                                                            recipientId:recipientId
                                                               deviceId:[deviceId intValue]];

    NSData *_Nullable serializedMessage;
    TSWhisperMessageType messageType;
    if (messageSend.isUDSend) {
        NSError *error;
        SMKSecretSessionCipher *_Nullable secretCipher =
            [[SMKSecretSessionCipher alloc] initWithSessionStore:self.primaryStorage
                                                     preKeyStore:self.primaryStorage
                                               signedPreKeyStore:self.primaryStorage
                                                   identityStore:self.identityManager
                                                           error:&error];
        if (error || !secretCipher) {
            OWSRaiseException(@"SecretSessionCipherFailure", @"Can't create secret session cipher.");
        }

        serializedMessage = [secretCipher throwswrapped_encryptMessageWithRecipientId:recipientId
                                                                             deviceId:deviceId.intValue
                                                                      paddedPlaintext:[plainText paddedMessageBody]
                                                                    senderCertificate:messageSend.senderCertificate
                                                                      protocolContext:transaction
                                                                                error:&error];
        SCKRaiseIfExceptionWrapperError(error);
        if (!serializedMessage || error) {
            OWSFailDebug(@"error while UD encrypting message: %@", error);
            return nil;
        }
        messageType = TSUnidentifiedSenderMessageType;
    } else {
        // This may throw an exception.
        id<CipherMessage> encryptedMessage =
            [cipher throws_encryptMessage:[plainText paddedMessageBody] protocolContext:transaction];
        serializedMessage = encryptedMessage.serialized;
        messageType = [self messageTypeForCipherMessage:encryptedMessage];
    }

    BOOL isSilent = message.isSilent;
    BOOL isOnline = message.isOnline;
    OWSMessageServiceParams *messageParams =
        [[OWSMessageServiceParams alloc] initWithType:messageType
                                          recipientId:recipientId
                                               device:[deviceId intValue]
                                              content:serializedMessage
                                             isSilent:isSilent
                                             isOnline:isOnline
                                       registrationId:[cipher throws_remoteRegistrationId:transaction]];

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
    switch (cipherMessage.cipherMessageType) {
        case CipherMessageType_Whisper:
            return TSEncryptedWhisperMessageType;
        case CipherMessageType_Prekey:
            return TSPreKeyWhisperMessageType;
        default:
            return TSUnknownMessageType;
    }
}

- (void)saveInfoMessageForGroupMessage:(TSOutgoingMessage *)message inThread:(TSThread *)thread
{
    OWSAssertDebug(message);
    OWSAssertDebug(thread);

    if (message.groupMetaMessage == TSGroupMetaMessageDeliver) {
        // TODO: Why is this necessary?
        [message save];
    } else if (message.groupMetaMessage == TSGroupMetaMessageQuit) {
        // MJK TODO - remove senderTimestamp
        [[[TSInfoMessage alloc] initWithTimestamp:message.timestamp
                                         inThread:thread
                                      messageType:TSInfoMessageTypeGroupQuit
                                    customMessage:message.customMessage] save];
    } else {
        // MJK TODO - remove senderTimestamp
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
                                                               transaction:transaction];
            }
        }];
        completionHandler();
    });
}

@end

@implementation OutgoingMessagePreparer

#pragma mark - Dependencies

+ (YapDatabaseConnection *)dbConnection
{
    return SSKEnvironment.shared.primaryStorage.dbReadWriteConnection;
}

#pragma mark -

+ (NSArray<NSString *> *)prepareMessageForSending:(TSOutgoingMessage *)message
                                      transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(message);
    OWSAssertDebug(transaction);

    NSMutableArray<NSString *> *attachmentIds = [NSMutableArray new];

    if (message.attachmentIds) {
        [attachmentIds addObjectsFromArray:message.attachmentIds];
    }

    if (message.quotedMessage) {
        // Though we currently only ever expect at most one thumbnail, the proto data model
        // suggests this could change. The logic is intended to work with multiple, but
        // if we ever actually want to send multiple, we should do more testing.
        NSArray<TSAttachmentStream *> *quotedThumbnailAttachments =
            [message.quotedMessage createThumbnailAttachmentsIfNecessaryWithTransaction:transaction];
        for (TSAttachmentStream *attachment in quotedThumbnailAttachments) {
            [attachmentIds addObject:attachment.uniqueId];
        }
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
        TSAttachment *attachment =
            [TSAttachment fetchObjectWithUniqueID:message.linkPreview.imageAttachmentId transaction:transaction];
        if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
            [attachmentIds addObject:attachment.uniqueId];
        } else {
            OWSFailDebug(@"unexpected attachment: %@", attachment);
        }
    }

    if (message.messageSticker.attachmentId != nil) {
        TSAttachment *attachment =
            [TSAttachment fetchObjectWithUniqueID:message.messageSticker.attachmentId transaction:transaction];
        if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
            [attachmentIds addObject:attachment.uniqueId];
        } else {
            OWSFailDebug(@"unexpected attachment: %@", attachment);
        }
    }

    // All outgoing messages should be saved at the time they are enqueued.
    [message saveWithTransaction:transaction];
    // When we start a message send, all "failed" recipients should be marked as "sending".
    [message updateWithMarkingAllUnsentRecipientsAsSendingWithTransaction:transaction];

    if (message.messageSticker != nil) {
        // Update "Recent Stickers" list to reflect sends.
        [StickerManager stickerWasSent:message.messageSticker.info transaction:transaction.asAnyWrite];
    }
    
    return attachmentIds;
}

+ (void)prepareAttachments:(NSArray<OWSOutgoingAttachmentInfo *> *)attachmentInfos
                 inMessage:(TSOutgoingMessage *)outgoingMessage
         completionHandler:(void (^)(NSError *_Nullable error))completionHandler
{
    OWSAssertDebug(attachmentInfos.count > 0);
    OWSAssertDebug(outgoingMessage);

    dispatch_async([OWSDispatch attachmentsQueue], ^{
        // Eventually we'll pad all outgoing attachments, but currently just stickers.
        // Currently this method is only used to process "body" attachments, which
        // cannot be sent along with stickers.
        OWSAssertDebug(outgoingMessage.messageSticker == nil);

        NSMutableArray<TSAttachmentStream *> *attachmentStreams = [NSMutableArray new];
        for (OWSOutgoingAttachmentInfo *attachmentInfo in attachmentInfos) {
            TSAttachmentStream *attachmentStream =
                [[TSAttachmentStream alloc] initWithContentType:attachmentInfo.contentType
                                                      byteCount:(UInt32)attachmentInfo.dataSource.dataLength
                                                 sourceFilename:attachmentInfo.sourceFilename
                                                        caption:attachmentInfo.caption
                                                 albumMessageId:attachmentInfo.albumMessageId
                                              isOutgoingSticker:NO];
            if (outgoingMessage.isVoiceMessage) {
                attachmentStream.attachmentType = TSAttachmentTypeVoiceMessage;
            }

            if (![attachmentStream writeDataSource:attachmentInfo.dataSource]) {
                OWSProdError([OWSAnalyticsEvents messageSenderErrorCouldNotWriteAttachment]);
                NSError *error = OWSErrorMakeWriteAttachmentDataError();
                completionHandler(error);
                return;
            }

            [attachmentStreams addObject:attachmentStream];
        }

        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            for (TSAttachmentStream *attachmentStream in attachmentStreams) {
                [outgoingMessage.attachmentIds addObject:attachmentStream.uniqueId];
                if (attachmentStream.sourceFilename) {
                    outgoingMessage.attachmentFilenameMap[attachmentStream.uniqueId] = attachmentStream.sourceFilename;
                }
            }
            [outgoingMessage saveWithTransaction:transaction];
            for (TSAttachmentStream *attachmentStream in attachmentStreams) {
                [attachmentStream saveWithTransaction:transaction];
            }
        }];

        completionHandler(nil);
    });
}

@end

NS_ASSUME_NONNULL_END
