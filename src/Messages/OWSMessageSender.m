//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageSender.h"
#import "ContactsUpdater.h"
#import "NSData+messagePadding.h"
#import "OWSDevice.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSError.h"
#import "OWSLegacyMessageServiceParams.h"
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
#import "TSStorageManager+IdentityKeyStore.h"
#import "TSStorageManager+PreKeyStore.h"
#import "TSStorageManager+SignedPreKeyStore.h"
#import "TSStorageManager+keyingMaterial.h"
#import "TSStorageManager+sessionStore.h"
#import "TSStorageManager.h"
#import "TSThread.h"
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/CipherMessage.h>
#import <AxolotlKit/PreKeyBundle.h>
#import <AxolotlKit/SessionBuilder.h>
#import <AxolotlKit/SessionCipher.h>
#import <TwistedOakCollapsingFutures/CollapsingFutures.h>

NS_ASSUME_NONNULL_BEGIN

#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(major, minor)                                                          \
    ([[NSProcessInfo processInfo]                                                                                      \
        isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){                                                    \
                                            .majorVersion = major, .minorVersion = minor, .patchVersion = 0 }])

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

typedef NS_ENUM(NSInteger, OWSSendMessageOperationState) {
    OWSSendMessageOperationStateNew,
    OWSSendMessageOperationStateExecuting,
    OWSSendMessageOperationStateFinished
};

@interface OWSMessageSender (OWSSendMessageOperation)

- (void)attemptToSendMessage:(TSOutgoingMessage *)message
                     success:(void (^)())successHandler
                     failure:(void (^)(NSError *error))failureHandler;

@end

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
            OWSCAssert(NO);
            return;
        }
        DDLogDebug(@"%@ succeeded.", strongSelf.tag);
        aSuccessHandler();
        [strongSelf markAsComplete];
    };

    _failureHandler = ^(NSError *_Nonnull error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            OWSCAssert(NO);
            return;
        }

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
    DDLogDebug(@"%@ remainingRetries: %lu", self.tag, remainingRetries);

    void (^retryableFailureHandler)(NSError *_Nonnull) = ^(NSError *_Nonnull error) {
        DDLogInfo(@"%@ Sending failed.", self.tag);
        if (remainingRetries > 0) {
            [self tryWithRemainingRetries:remainingRetries - 1];
        } else {
            DDLogWarn(@"%@ Too many failures. Giving up sending.", self.tag);
            self.failureHandler(error);
        }
    };

    [self.messageSender attemptToSendMessage:self.message success:self.successHandler failure:retryableFailureHandler];
}

- (void)markAsComplete
{
    [self willChangeValueForKey:OWSSendMessageOperationKeyIsExecuting];
    [self willChangeValueForKey:OWSSendMessageOperationKeyIsFinished];
    self.operationState = OWSSendMessageOperationStateFinished;
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
@property (nonatomic, readonly) OWSUploadingService *uploadingService;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (nonatomic, readonly) id<ContactsManagerProtocol> contactsManager;
@property (nonatomic, readonly) ContactsUpdater *contactsUpdater;
@property (nonatomic, readonly) OWSDisappearingMessagesJob *disappearingMessagesJob;
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
    _disappearingMessagesJob = [[OWSDisappearingMessagesJob alloc] initWithStorageManager:storageManager];

    OWSSingletonAssert();

    return self;
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
    AssertIsOnMainThread();

    [self saveMessage:message withState:TSOutgoingMessageStateAttemptingOut];
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
                     failure:(void (^)(NSError *error))failureHandler
{
    DDLogDebug(@"%@ sending message: %@", self.tag, message.debugDescription);
    void (^markAndFailureHandler)(NSError *error) = ^(NSError *error) {
        [self saveMessage:message withError:error];
        failureHandler(error);
    };

    [self ensureAnyAttachmentsUploaded:message
                               success:^() {
                                   [self deliverMessage:message success:successHandler failure:markAndFailureHandler];
                               }
                               failure:markAndFailureHandler];
}

- (void)ensureAnyAttachmentsUploaded:(TSOutgoingMessage *)message
                             success:(void (^)())successHandler
                             failure:(void (^)(NSError *error))failureHandler
{
    if (!message.hasAttachments) {
        DDLogDebug(@"%@ No attachments for message: %@", self.tag, message);
        return successHandler();
    }

    TSAttachmentStream *attachmentStream =
        [TSAttachmentStream fetchObjectWithUniqueID:message.attachmentIds.firstObject];

    if (!attachmentStream) {
        DDLogError(@"%@ Unable to find local saved attachment to upload.", self.tag);
        NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
        return failureHandler(error);
    }

    [self.uploadingService uploadAttachmentStream:attachmentStream
                                          message:message
                                          success:successHandler
                                          failure:failureHandler];
}

- (void)sendTemporaryAttachmentData:(NSData *)attachmentData
                        contentType:(NSString *)contentType
                          inMessage:(TSOutgoingMessage *)message
                            success:(void (^)())successHandler
                            failure:(void (^)(NSError *error))failureHandler
{
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

    [self sendAttachmentData:attachmentData
                 contentType:contentType
                   inMessage:message
                     success:successWithDeleteHandler
                     failure:failureWithDeleteHandler];
}

- (void)sendAttachmentData:(NSData *)data
               contentType:(NSString *)contentType
                 inMessage:(TSOutgoingMessage *)message
                   success:(void (^)())successHandler
                   failure:(void (^)(NSError *error))failureHandler
{
    // There's an odd bug wherein instances of NSData/Data created in Swift
    // code reliably crash on iOS 9 when calling [NSData writeToFile:...].
    // We can avoid these crashes by simply copying the Data.
    //
    // TODO: Move the iOSVersion header to SSK.
    NSData *dataCopy = (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(10, 0) ? data : [data copy]);

    dispatch_async([OWSDispatch attachmentsQueue], ^{
        TSAttachmentStream *attachmentStream = [[TSAttachmentStream alloc] initWithContentType:contentType];

        NSError *error;
        [attachmentStream writeData:dataCopy error:&error];
        if (error) {
            DDLogError(@"%@ Failed to write data for outgoing attachment with error:%@", self.tag, error);
            return failureHandler(error);
        }

        [attachmentStream save];
        [message.attachmentIds addObject:attachmentStream.uniqueId];
        [message save];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self sendMessage:message success:successHandler failure:failureHandler];
        });
    });
}

- (void)resendMessageFromKeyError:(TSInvalidIdentityKeySendingErrorMessage *)errorMessage
                          success:(void (^)())successHandler
                          failure:(void (^)(NSError *error))failureHandler
{
    TSOutgoingMessage *message = [TSOutgoingMessage fetchObjectWithUniqueID:errorMessage.messageId];

    // Here we remove the existing error message because sending a new message will either
    //  1.) succeed and create a new successful message in the thread or...
    //  2.) fail and create a new identical error message in the thread.
    [errorMessage remove];

    if ([errorMessage.thread isKindOfClass:[TSContactThread class]]) {
        return [self sendMessage:message success:successHandler failure:failureHandler];
    }

    // else it's a GroupThread
    dispatch_async([OWSDispatch sendingQueue], ^{

        // Avoid spamming entire group when resending failed message.
        SignalRecipient *failedRecipient = [SignalRecipient fetchObjectWithUniqueID:errorMessage.recipientId];

        // Normally marking as unsent is handled in sendMessage happy path, but beacuse we're skipping the common entry
        // point to message sending in order to send to a single recipient, we have to handle it ourselves.
        void (^markAndFailureHandler)(NSError *error) = ^(NSError *error) {
            [self saveMessage:message withError:error];
            failureHandler(error);
        };

        [self groupSend:@[ failedRecipient ]
                message:message
                 thread:message.thread
                success:successHandler
                failure:markAndFailureHandler];
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
        DDLogError(@"%@ Unknown error finding contacts", self.tag);
        *error = OWSErrorMakeFailedToSendOutgoingMessageError();
    }

    return [recipients copy];
}

- (void)deliverMessage:(TSOutgoingMessage *)message
               success:(void (^)())successHandler
               failure:(void (^)(NSError *error))failureHandler
{
    TSThread *thread = message.thread;

    dispatch_async([OWSDispatch sendingQueue], ^{
        if ([thread isKindOfClass:[TSGroupThread class]]) {
            TSGroupThread *gThread = (TSGroupThread *)thread;

            NSError *error;
            NSArray<SignalRecipient *> *recipients =
                [self getRecipients:gThread.groupModel.groupMemberIds error:&error];

            if (recipients.count == 0) {
                if (error) {
                    return failureHandler(error);
                } else {
                    DDLogError(@"%@ Unknown error finding contacts", self.tag);
                    return failureHandler(OWSErrorMakeFailedToSendOutgoingMessageError());
                }
            }

            [self groupSend:recipients message:message thread:gThread success:successHandler failure:failureHandler];

        } else if ([thread isKindOfClass:[TSContactThread class]]
            || [message isKindOfClass:[OWSOutgoingSyncMessage class]]) {

            TSContactThread *contactThread = (TSContactThread *)thread;
            if ([contactThread.contactIdentifier isEqualToString:self.storageManager.localNumber]
                && ![message isKindOfClass:[OWSOutgoingSyncMessage class]]) {

                [self handleSendToMyself:message];
                successHandler();
                return;
            }

            NSString *recipientContactId = [message isKindOfClass:[OWSOutgoingSyncMessage class]]
                ? self.storageManager.localNumber
                : contactThread.contactIdentifier;

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

                    DDLogError(@"%@ contact lookup failed with error: %@", self.tag, error);
                    return failureHandler(error);
                }
            }

            if (!recipient) {
                NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
                DDLogWarn(@"recipient contact still not found after attempting lookup.");
                return failureHandler(error);
            }

            [self sendMessage:message
                    recipient:recipient
                       thread:thread
                     attempts:OWSMessageSenderRetryAttempts
                      success:successHandler
                      failure:failureHandler];
        } else {
            DDLogError(@"%@ Unexpected unhandlable message: %@", self.tag, message);
            NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
            failureHandler(error);
        }
    });
}

/// For group sends, we're using chained futures to make the code more readable.

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
          failure:(void (^)(NSError *error))failureHandler
{
    [self saveGroupMessage:message inThread:thread];
    NSMutableArray<TOCFuture *> *futures = [NSMutableArray array];

    for (SignalRecipient *rec in recipients) {
        // we don't need to send the message to ourselves, but otherwise we send
        if (![[rec uniqueId] isEqualToString:[TSStorageManager localNumber]]) {
            [futures addObject:[self sendMessageFuture:message recipient:rec thread:thread]];
        }
    }

    TOCFuture *completionFuture = futures.toc_thenAll;

    [completionFuture thenDo:^(id value) {
        successHandler();
    }];

    [completionFuture catchDo:^(id failure) {
        // failure from toc_thenAll yeilds an array of failed Futures, rather than the future's failure.
        if ([failure isKindOfClass:[NSArray class]]) {
            NSArray *errors = (NSArray *)failure;
            for (TOCFuture *failedFuture in errors) {
                if (!failedFuture.hasFailed) {
                    // If at least one send succeeded, don't show message as failed.
                    // Else user will tap-to-resend to all recipients, including those that already received the
                    // message.
                    return successHandler();
                }
            }

            // At this point, all recipients must have failed.
            // But we have all this verbose type checking because TOCFuture doesn't expose type information.
            id lastError = errors.lastObject;
            if ([lastError isKindOfClass:[TOCFuture class]]) {
                TOCFuture *failedFuture = (TOCFuture *)lastError;
                if (failedFuture.hasFailed) {
                    id failureResult = failedFuture.forceGetFailure;
                    if ([failureResult isKindOfClass:[NSError class]]) {
                        return failureHandler((NSError *)failureResult);
                    }
                }
            }
        }

        DDLogWarn(@"%@ Unexpected generic failure: %@", self.tag, failure);
        return failureHandler(OWSErrorMakeFailedToSendOutgoingMessageError());
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
            failure:(void (^)(NSError *error))failureHandler
{
    DDLogDebug(@"%@ sending message to service: %@", self.tag, message.debugDescription);

    if ([TSPreKeyManager isAppLockedDueToPreKeyUpdateFailures]) {
        OWSAnalyticsError(@"Message send failed due to prekey update failures");

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

        DDLogError(@"%@ Message send failed due to repeated inability to update prekeys.", self.tag);
        return failureHandler(OWSErrorMakeMessageSendDisabledDueToPreKeyUpdateFailuresError());
    }

    if (remainingAttempts <= 0) {
        // We should always fail with a specific error.
        DDLogError(@"%@ Unexpected generic failure.", self.tag);
        return failureHandler(OWSErrorMakeFailedToSendOutgoingMessageError());
    }
    remainingAttempts -= 1;

    NSArray<NSDictionary *> *deviceMessages;
    @try {
        deviceMessages = [self deviceMessages:message forRecipient:recipient inThread:thread];
    } @catch (NSException *exception) {
        deviceMessages = @[];
        if ([exception.name isEqualToString:UntrustedIdentityKeyException]) {
            [[TSInvalidIdentityKeySendingErrorMessage
                untrustedKeyWithOutgoingMessage:message
                                       inThread:thread
                                   forRecipient:exception.userInfo[TSInvalidRecipientKey]
                                   preKeyBundle:exception.userInfo[TSInvalidPreKeyBundleKey]] save];
            NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeUntrustedIdentityKey,
                NSLocalizedString(@"FAILED_SENDING_BECAUSE_UNTRUSTED_IDENTITY_KEY",
                    @"action sheet header when re-sending message which failed because of untrusted identity keys"));
            return failureHandler(error);
        }

        if ([exception.name isEqualToString:OWSMessageSenderRateLimitedException]) {
            NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeSignalServiceRateLimited,
                NSLocalizedString(@"FAILED_SENDING_BECAUSE_RATE_LIMIT",
                    @"action sheet header when re-sending message which failed because of too many attempts"));
            return failureHandler(error);
        }

        if (remainingAttempts == 0) {
            DDLogWarn(
                @"%@ Terminal failure to build any device messages. Giving up with exception:%@", self.tag, exception);
            [self processException:exception outgoingMessage:message inThread:thread];
            NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
            return failureHandler(error);
        }
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
            DDLogDebug(@"%@ failure sending to service: %@", self.tag, message.debugDescription);
            [DDLog flushLog];

            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            long statuscode = response.statusCode;
            NSData *responseData = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];

            void (^retrySend)() = ^void() {
                if (remainingAttempts <= 0) {
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
                    return failureHandler(error);
                }
                case 404: {
                    [self unregisteredRecipient:recipient message:message thread:thread];
                    NSError *error = OWSErrorMakeNoSuchSignalRecipientError();
                    return failureHandler(error);
                }
                case 409: {
                    // Mismatched devices
                    DDLogWarn(@"%@ Mismatch Devices.", self.tag);

                    NSError *error;
                    NSDictionary *serializedResponse =
                        [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&error];
                    if (error) {
                        DDLogError(@"%@ Failed to serialize response of mismatched devices: %@", self.tag, error);
                        return failureHandler(error);
                    }

                    [self handleMismatchedDevices:serializedResponse recipient:recipient];
                    retrySend();
                    break;
                }
                case 410: {
                    // staledevices
                    DDLogWarn(@"Stale devices");

                    if (!responseData) {
                        DDLogWarn(@"Stale devices but server didn't specify devices in response.");
                        NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                        return failureHandler(error);
                    }

                    [self handleStaleDevicesWithResponse:responseData recipientId:recipient.uniqueId];
                    retrySend();
                    break;
                }
                default:
                    retrySend();
                    break;
            }
        }];
}

- (void)handleMismatchedDevices:(NSDictionary *)dictionary recipient:(SignalRecipient *)recipient
{
    NSArray *extraDevices = [dictionary objectForKey:@"extraDevices"];
    NSArray *missingDevices = [dictionary objectForKey:@"missingDevices"];

    if (extraDevices && extraDevices.count > 0) {
        for (NSNumber *extraDeviceId in extraDevices) {
            [self.storageManager deleteSessionForContact:recipient.uniqueId deviceId:extraDeviceId.intValue];
        }

        [recipient removeDevices:[NSSet setWithArray:extraDevices]];
    }

    if (missingDevices && missingDevices.count > 0) {
        [recipient addDevices:[NSSet setWithArray:missingDevices]];
    }

    [recipient save];
}

- (void)handleMessageSentLocally:(TSOutgoingMessage *)message
{
    [self saveMessage:message withState:TSOutgoingMessageStateSent];
    if (message.shouldSyncTranscript) {
        // TODO: I suspect we shouldn't optimistically set hasSyncedTranscript.
        //       We could set this in a success handler for [sendSyncTranscriptForMessage:].

        message.hasSyncedTranscript = YES;
        [self sendSyncTranscriptForMessage:message];
    }

    [self.disappearingMessagesJob setExpirationForMessage:message];
}

- (void)handleMessageSentRemotely:(TSOutgoingMessage *)message sentAt:(uint64_t)sentAt
{
    [self saveMessage:message withState:TSOutgoingMessageStateDelivered];
    [self becomeConsistentWithDisappearingConfigurationForMessage:message];
    [self.disappearingMessagesJob setExpirationForMessage:message expirationStartedAt:sentAt];
}

- (void)becomeConsistentWithDisappearingConfigurationForMessage:(TSOutgoingMessage *)outgoingMessage
{
    [self.disappearingMessagesJob becomeConsistentWithConfigurationForMessage:outgoingMessage
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
            DDLogInfo(@"Failed to send sync transcript:%@", error);
        }];
}

- (NSArray<NSDictionary *> *)deviceMessages:(TSOutgoingMessage *)message
                               forRecipient:(SignalRecipient *)recipient
                                   inThread:(TSThread *)thread
{
    NSMutableArray *messagesArray = [NSMutableArray arrayWithCapacity:recipient.devices.count];
    NSData *plainText = [message buildPlainTextData];

    for (NSNumber *deviceNumber in recipient.devices) {
        @try {
            __block NSDictionary *messageDict;
            __block NSException *encryptionException;
            // Mutating session state is not thread safe, so we operate on a serial queue, shared with decryption
            // operations.
            dispatch_sync([OWSDispatch sessionCipher], ^{
                @try {
                    messageDict = [self encryptedMessageWithPlaintext:plainText
                                                          toRecipient:recipient.uniqueId
                                                             deviceId:deviceNumber
                                                        keyingStorage:[TSStorageManager sharedManager]
                                                               legacy:message.isLegacyMessage];
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
                                         legacy:(BOOL)isLegacymessage
{
    if (![storage containsSession:identifier deviceId:[deviceNumber intValue]]) {
        __block dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        __block PreKeyBundle *bundle;
        __block NSException *exception;
        [self.networkManager makeRequest:[[TSRecipientPrekeyRequest alloc] initWithRecipient:identifier
                                                                                    deviceId:[deviceNumber stringValue]]
            success:^(NSURLSessionDataTask *task, id responseObject) {
                bundle = [PreKeyBundle preKeyBundleFromDictionary:responseObject forDeviceNumber:deviceNumber];
                dispatch_semaphore_signal(sema);
            }
            failure:^(NSURLSessionDataTask *task, NSError *error) {
                DDLogError(@"Server replied on PreKeyBundle request with error: %@", error);
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
                                                                  identityKeyStore:storage
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
                                                       identityKeyStore:storage
                                                            recipientId:identifier
                                                               deviceId:[deviceNumber intValue]];

    id<CipherMessage> encryptedMessage = [cipher encryptMessage:[plainText paddedMessageBody]];


    NSData *serializedMessage = encryptedMessage.serialized;
    TSWhisperMessageType messageType = [self messageTypeForCipherMessage:encryptedMessage];

    OWSMessageServiceParams *messageParams;
    // DEPRECATED - Remove after all clients have been upgraded.
    if (isLegacymessage) {
        messageParams = [[OWSLegacyMessageServiceParams alloc] initWithType:messageType
                                                                recipientId:identifier
                                                                     device:[deviceNumber intValue]
                                                                       body:serializedMessage
                                                             registrationId:cipher.remoteRegistrationId];
    } else {
        messageParams = [[OWSMessageServiceParams alloc] initWithType:messageType
                                                          recipientId:identifier
                                                               device:[deviceNumber intValue]
                                                              content:serializedMessage
                                                       registrationId:cipher.remoteRegistrationId];
    }

    NSError *error;
    NSDictionary *jsonDict = [MTLJSONAdapter JSONDictionaryFromModel:messageParams error:&error];

    if (error) {
        DDLogError(@"Error while making JSON dictionary of message: %@", error.debugDescription);
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

- (void)saveMessage:(TSOutgoingMessage *)message withState:(TSOutgoingMessageState)state
{
    message.messageState = state;
    [message save];
}

- (void)saveMessage:(TSOutgoingMessage *)message withError:(NSError *)error
{
    message.messageState = TSOutgoingMessageStateUnsent;
    [message setSendingError:error];
    [message save];
}

- (void)saveGroupMessage:(TSOutgoingMessage *)message inThread:(TSThread *)thread
{
    if (message.groupMetaMessage == TSGroupMessageDeliver) {
        [self saveMessage:message withState:message.messageState];
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

- (void)handleStaleDevicesWithResponse:(NSData *)responseData recipientId:(NSString *)identifier
{
    dispatch_async([OWSDispatch sendingQueue], ^{
        NSDictionary *serialization = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil];
        NSArray *devices = serialization[@"staleDevices"];

        if (!([devices count] > 0)) {
            return;
        }

        for (NSUInteger i = 0; i < [devices count]; i++) {
            int deviceNumber = [devices[i] intValue];
            [[TSStorageManager sharedManager] deleteSessionForContact:identifier deviceId:deviceNumber];
        }
    });
}

- (void)processException:(NSException *)exception
         outgoingMessage:(TSOutgoingMessage *)message
                inThread:(TSThread *)thread
{
    DDLogWarn(@"%@ Got exception: %@", self.tag, exception);

    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSErrorMessage *errorMessage;

        if (message.groupMetaMessage == TSGroupMessageNone) {
            // Only update this with exception if it is not a group message as group
            // messages may except for one group
            // send but not another and the UI doesn't know how to handle that
            [message setMessageState:TSOutgoingMessageStateUnsent];
            [message saveWithTransaction:transaction];
        }

        [errorMessage saveWithTransaction:transaction];
    }];
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
