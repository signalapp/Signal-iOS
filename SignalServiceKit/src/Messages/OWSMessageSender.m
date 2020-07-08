//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageSender.h"
#import "AppContext.h"
#import "NSData+keyVersionByte.h"
#import "NSData+messagePadding.h"
#import "NSError+OWSOperation.h"
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
#import "OWSRequestFactory.h"
#import "OWSUploadOperation.h"
#import "PreKeyBundle+jsonDict.h"
#import "ProfileManagerProtocol.h"
#import "SSKEnvironment.h"
#import "SSKPreKeyStore.h"
#import "SSKSessionStore.h"
#import "SSKSignedPreKeyStore.h"
#import "SignalRecipient.h"
#import "TSAccountManager.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TSIncomingMessage.h"
#import "TSInfoMessage.h"
#import "TSNetworkManager.h"
#import "TSOutgoingMessage.h"
#import "TSPreKeyManager.h"
#import "TSQuotedMessage.h"
#import "TSRequest.h"
#import "TSSocketManager.h"
#import "TSThread.h"
#import <AFNetworking/AFURLResponseSerialization.h>
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

@implementation OWSOutgoingAttachmentInfo

- (instancetype)initWithDataSource:(id<DataSource>)dataSource
                       contentType:(NSString *)contentType
                    sourceFilename:(nullable NSString *)sourceFilename
                           caption:(nullable NSString *)caption
                    albumMessageId:(nullable NSString *)albumMessageId
                      isBorderless:(BOOL)isBorderless
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
    }

    [attachmentStream writeConsumingDataSource:self.dataSource error:error];
    if (*error != nil) {
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
 * Used by `OWSMessageSender` to serialize message sending, ensuring that messages are emitted in the order they
 * were sent.
 */
@interface OWSSendMessageOperation : OWSOperation

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithMessage:(TSOutgoingMessage *)message
                  messageSender:(OWSMessageSender *)messageSender
                        success:(void (^)(void))aSuccessHandler
                        failure:(void (^)(NSError *error))aFailureHandler NS_DESIGNATED_INITIALIZER;

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
@property (nonatomic, readonly) void (^successHandler)(void);
@property (nonatomic, readonly) void (^failureHandler)(NSError *error);

@end

#pragma mark -

@implementation OWSSendMessageOperation

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

- (instancetype)initWithMessage:(TSOutgoingMessage *)message
                  messageSender:(OWSMessageSender *)messageSender
                        success:(void (^)(void))successHandler
                        failure:(void (^)(NSError *error))failureHandler
{
    self = [super init];
    if (!self) {
        return self;
    }

    _message = message;
    _messageSender = messageSender;
    _successHandler = successHandler;
    _failureHandler = failureHandler;

    self.queuePriority = [OWSMessageSender queuePriorityForMessage:message];

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
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            for (TSAttachment *attachment in [self.message allAttachmentsWithTransaction:transaction.unwrapGrdbRead]) {
                if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
                    error = OWSErrorMakeFailedToSendOutgoingMessageError();
                    break;
                }

                TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;
                OWSAssertDebug(attachmentStream);
                OWSAssertDebug(attachmentStream.serverId || attachmentStream.cdnKey.length > 0);
                OWSAssertDebug(attachmentStream.isUploaded);
            }
        }];
    }

    return error;
}

- (void)run
{
    if (SSKAppExpiry.isExpired) {
        OWSLogWarn(@"Unable to send because the application has expired.");
        NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeAppExpired,
            NSLocalizedString(
                @"ERROR_SENDING_EXPIRED", @"Error indicating a send failure due to an expired application."));
        error.isRetryable = NO;
        [self reportError:error];
        return;
    }

    if (TSAccountManager.sharedInstance.isDeregistered) {
        OWSLogWarn(@"Unable to send because the application is deregistered.");
        NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeAppDeregistered,
            TSAccountManager.sharedInstance.isPrimaryDevice
                ? NSLocalizedString(@"ERROR_SENDING_DEREGISTERED",
                    @"Error indicating a send failure due to a deregistered application.")
                : NSLocalizedString(
                    @"ERROR_SENDING_DELINKED", @"Error indicating a send failure due to a delinked application."));
        error.isRetryable = NO;
        [self reportError:error];
        return;
    }

    // If the message has been deleted, abort send.
    __block TSInteraction *_Nullable latestCopy;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        latestCopy = [TSInteraction anyFetchWithUniqueId:self.message.uniqueId transaction:transaction];
    }];
    if (self.message.shouldBeSaved && latestCopy == nil) {
        OWSLogInfo(@"aborting message send; message deleted.");
        NSError *error = OWSErrorWithCodeDescription(
            OWSErrorCodeMessageDeletedBeforeSent, @"Message was deleted before it could be sent.");
        error.isFatal = YES;
        error.isRetryable = NO;
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

@property (atomic, readonly) NSMutableDictionary<NSString *, NSOperationQueue *> *sendingQueueMap;

@end

#pragma mark -

@implementation OWSMessageSender

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _sendingQueueMap = [NSMutableDictionary new];

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

- (SSKSessionStore *)sessionStore
{
    return SSKEnvironment.shared.sessionStore;
}

- (SSKPreKeyStore *)preKeyStore
{
    return SSKEnvironment.shared.preKeyStore;
}

- (SSKSignedPreKeyStore *)signedPreKeyStore
{
    return SSKEnvironment.shared.signedPreKeyStore;
}

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

+ (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (id<ProfileManagerProtocol>)profileManager
{
    return SSKEnvironment.shared.profileManager;
}

#pragma mark -

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
            sendingQueue.name = [NSString stringWithFormat:@"%@:%@", self.logTag, queueKey];
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
        operationQueue.name = @"MessageSender.global";
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
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    failureHandler(error);
                });
                return;
            }
        }

        OWSAssertDebug(message);
        if (message.body.length > 0) {
            OWSAssertDebug(
                [message.body lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= kOversizeTextMessageSizeThreshold);
        }

        OWSSendMessageOperation *sendMessageOperation =
            [[OWSSendMessageOperation alloc] initWithMessage:message
                                               messageSender:self
                                                     success:successHandler
                                                     failure:failureHandler];

        OWSAssertDebug(outgoingMessagePreparer.savedAttachmentIds != nil);
        for (NSString *attachmentId in outgoingMessagePreparer.savedAttachmentIds) {
            OWSUploadOperation *uploadAttachmentOperation =
                [[OWSUploadOperation alloc] initWithAttachmentId:attachmentId];
            [sendMessageOperation addDependency:uploadAttachmentOperation];
            [OWSUploadOperation.uploadQueue addOperation:uploadAttachmentOperation];
        }

        NSOperationQueue *sendingQueue = [self sendingQueueForMessage:message];
        NSOperationQueue *globalSendingQueue = OWSMessageSender.globalSendingQueue;

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
                                                                                         isBorderless:NO];
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

    [self.udManager ensureSenderCertificateWithCertificateExpirationPolicy:OWSUDCertificateExpirationPolicyPermissive
        success:^(SMKSenderCertificate *senderCertificate) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self sendMessageToService:message senderCertificate:senderCertificate success:success failure:failure];
            });
        }
        failure:^(NSError *error) {
            OWSLogError(@"Could not obtain UD sender certificate: %@", error);

            if (IsNetworkConnectivityFailure(error)) {
                return failure(error);
            } else {
                // Proceed using non-UD message sends.
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    [self sendMessageToService:message senderCertificate:nil success:success failure:failure];
                });
            }
        }];
}

- (nullable NSArray<SignalServiceAddress *> *)unsentRecipientsForMessage:(TSOutgoingMessage *)message
                                                                  thread:(TSThread *)thread
                                                                   error:(NSError **)errorHandle
{
    OWSAssertDebug(!NSThread.isMainThread);
    OWSAssertDebug(message);
    OWSAssertDebug(thread);
    OWSAssertDebug(errorHandle);

    NSMutableSet<SignalServiceAddress *> *recipientAddresses = [NSMutableSet new];
    if ([message isKindOfClass:[OWSOutgoingSyncMessage class]]) {
        [recipientAddresses addObject:self.tsAccountManager.localAddress];
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

        [recipientAddresses addObjectsFromArray:message.sendingRecipientAddresses];

        // Only send to members in the latest known group member list...
        NSMutableSet<SignalServiceAddress *> *currentThreadRecipients = [NSMutableSet new];
        [currentThreadRecipients addObjectsFromArray:groupThread.groupModel.groupMembers];
        if ([GroupManager shouldMessageHaveAdditionalRecipients:message groupThread:groupThread]) {
            // ...or latest known list of "additional recipients".
            NSSet<SignalServiceAddress *> *additionalRecipients = groupThread.groupModel.groupMembership.pendingMembers;
            [currentThreadRecipients unionSet:additionalRecipients];
        }
        [recipientAddresses intersectSet:currentThreadRecipients];

        if ([recipientAddresses containsObject:self.tsAccountManager.localAddress]) {
            OWSFailDebug(@"Message send recipients should not include self.");
        }
    } else if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        SignalServiceAddress *recipientAddress = contactThread.contactAddress;

        // Treat 1:1 sends to blocked contacts as failures.
        // If we block a user, don't send 1:1 messages to them. The UI
        // should prevent this from occurring, but in some edge cases
        // you might, for example, have a pending outgoing message when
        // you block them.
        OWSAssertDebug(recipientAddress);
        if ([self.blockingManager isAddressBlocked:recipientAddress]) {
            OWSLogInfo(@"skipping 1:1 send to blocked contact: %@", recipientAddress);
            NSError *error = OWSErrorMakeMessageSendFailedDueToBlockListError();
            [error setIsRetryable:NO];
            *errorHandle = error;
            return nil;
        }

        [recipientAddresses addObject:recipientAddress];

        if ([recipientAddresses containsObject:self.tsAccountManager.localAddress]) {
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

    [recipientAddresses minusSet:self.blockingManager.blockedAddresses];
    return recipientAddresses.allObjects;
}

- (NSArray<SignalRecipient *> *)recipientsForAddresses:(NSArray<SignalServiceAddress *> *)addresses
{
    OWSAssertDebug(!NSThread.isMainThread);
    OWSAssertDebug(addresses.count > 0);

    NSMutableArray<SignalRecipient *> *recipients = [NSMutableArray new];
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        for (SignalServiceAddress *address in addresses) {
            SignalRecipient *recipient = [SignalRecipient getOrBuildUnsavedRecipientForAddress:address
                                                                                   transaction:transaction];
            [recipients addObject:recipient];
        }
    }];
    return [recipients copy];
}

- (AnyPromise *)unlockPreKeyUpdateFailuresPromise
{
    OWSAssertDebug(!NSThread.isMainThread);

    if (![TSPreKeyManager isAppLockedDueToPreKeyUpdateFailures]) {
        return [AnyPromise promiseWithValue:@(1)];
    }

    OWSLogInfo(@"Trying to unlock prekey update.");

    return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            OWSProdError([OWSAnalyticsEvents messageSendErrorFailedDueToPrekeyUpdateFailures]);

            // Retry prekey update every time user tries to send a message while app
            // is disabled due to prekey update failures.
            //
            // Only try to update the signed prekey; updating it is sufficient to
            // re-enable message sending.
            [TSPreKeyManager
                rotateSignedPreKeyWithSuccess:^{
                    OWSLogInfo(@"New prekeys registered with server.");
                    resolve(@(1));
                }
                failure:^(NSError *error) {
                    OWSLogWarn(@"Failed to update prekeys with the server: %@", error);
                    resolve(error);
                }];
        });
    }];
}

- (AnyPromise *)sendPromiseForRecipients:(NSArray<SignalRecipient *> *)recipients
                                 message:(TSOutgoingMessage *)message
                                  thread:(TSThread *)thread
                       senderCertificate:(nullable SMKSenderCertificate *)senderCertificate
                          sendErrorBlock:(void (^_Nonnull)(SignalRecipient *recipient, NSError *))sendErrorBlock
{
    OWSAssertDebug(!NSThread.isMainThread);
    OWSAssertDebug(recipients.count > 0);
    OWSAssertDebug(message);
    OWSAssertDebug(thread);

    // 1. gather "ud sending access" using a single write transaction.
    NSMutableDictionary<SignalServiceAddress *, OWSUDSendingAccess *> *sendingAccessMap = [NSMutableDictionary new];
    if (senderCertificate != nil) {
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            for (SignalRecipient *recipient in recipients) {
                if (!recipient.address.isLocalAddress) {
                    sendingAccessMap[recipient.address] = [self.udManager udSendingAccessForAddress:recipient.address
                                                                                  requireSyncAccess:YES
                                                                                  senderCertificate:senderCertificate
                                                                                        transaction:transaction];
                }
            }
        });
    }

    // 2. Build a "OWSMessageSend" for each recipient.
    NSMutableArray<OWSMessageSend *> *messageSends = [NSMutableArray new];
    for (SignalRecipient *recipient in recipients) {
        OWSUDSendingAccess *_Nullable udSendingAccess = sendingAccessMap[recipient.address];
        OWSMessageSend *messageSend = [[OWSMessageSend alloc] initWithMessage:message
                                                                       thread:thread
                                                                    recipient:recipient
                                                              udSendingAccess:udSendingAccess
                                                                 localAddress:self.tsAccountManager.localAddress
                                                               sendErrorBlock:^(NSError *error) {
                                                                   sendErrorBlock(recipient, error);
                                                               }];
        [messageSends addObject:messageSend];
    }

    // 3. Before kicking of the per-recipient message sends, try
    // to ensure sessions for all recipient devices in parallel.
    return
        [MessageSending ensureSessionsforMessageSendsObjc:messageSends ignoreErrors:YES].thenInBackground(^(id value) {
            // 4. Perform the per-recipient message sends.
            NSMutableArray<AnyPromise *> *sendPromises = [NSMutableArray array];
            for (OWSMessageSend *messageSend in messageSends) {
                [self sendMessageToRecipient:messageSend];
                [sendPromises addObject:messageSend.asAnyPromise];
            }

            // We use PMKJoin(), not PMKWhen(), because we don't want the
            // completion promise to execute until _all_ send promises
            // have either succeeded or failed. PMKWhen() executes as
            // soon as any of its input promises fail.
            return PMKJoin(sendPromises);
        });
}

- (void)sendMessageToService:(TSOutgoingMessage *)message
           senderCertificate:(nullable SMKSenderCertificate *)senderCertificate
                     success:(void (^)(void))successHandlerParam
                     failure:(RetryableFailureHandler)failureHandlerParam
{
    OWSAssertDebug(!NSThread.isMainThread);

    void (^successHandler)(void) = ^() {
        [self handleMessageSentLocally:message
            success:^{
                successHandlerParam();
            }
            failure:^(NSError *error) {
                OWSLogError(
                    @"Error sending sync message for message: %@ timestamp: %llu", message.class, message.timestamp);

                failureHandlerParam(error);
            }];
    };
    void (^failureHandler)(NSError *) = ^(NSError *error) {
        if (message.wasSentToAnyRecipient) {
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
            return;
        }
        failureHandlerParam(error);
    };

    // This should not be nil, even for legacy queued messages.
    TSThread *_Nullable thread = [self threadForMessageWithSneakyTransaction:message];
    OWSAssertDebug(thread != nil);

    if (!thread) {
        OWSFailDebug(@"Missing thread.");

        // This thread has been deleted since the message was enqueued.
        NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeMessageSendNoValidRecipients,
            NSLocalizedString(@"ERROR_DESCRIPTION_NO_VALID_RECIPIENTS",
                @"Error indicating that an outgoing message had no valid recipients."));
        [error setIsRetryable:NO];
        return failureHandler(error);
    }

    TSContactThread *_Nullable contactThread;
    if ([thread isKindOfClass:[TSContactThread class]]) {
        contactThread = (TSContactThread *)thread;
    }

    // In the "self-send" aka "Note to Self" special case, we only
    // need to send a sync message with a delivery receipt.
    BOOL isSyncMessage = [message isKindOfClass:[OWSOutgoingSyncMessage class]];
    if (contactThread && contactThread.contactAddress.isLocalAddress && !isSyncMessage) {
        // Send to self.
        OWSAssertDebug(message.recipientAddresses.count == 1);
        // Don't mark self-sent messages as read (or sent) until the sync transcript is sent.
        successHandler();
        return;
    }

    NSError *error;
    NSArray<SignalServiceAddress *> *_Nullable recipientAddresses = [self unsentRecipientsForMessage:message
                                                                                              thread:thread
                                                                                               error:&error];
    if (error || !recipientAddresses) {
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
    NSMutableSet<SignalServiceAddress *> *obsoleteRecipientAddresses =
        [NSMutableSet setWithArray:message.sendingRecipientAddresses];
    [obsoleteRecipientAddresses minusSet:[NSSet setWithArray:recipientAddresses]];
    if (obsoleteRecipientAddresses.count > 0) {
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            for (SignalServiceAddress *obsoleteAddress in obsoleteRecipientAddresses) {
                // Mark this recipient as "skipped".
                [message updateWithSkippedRecipient:obsoleteAddress transaction:transaction];
            }
        });
    }

    if (recipientAddresses.count < 1) {
        // All recipients are already sent or can be skipped.
        successHandler();
        return;
    }

    NSArray<SignalRecipient *> *recipients = [self recipientsForAddresses:recipientAddresses];

    BOOL isGroupSend = thread.isGroupThread;
    NSMutableArray<NSError *> *sendErrors = [NSMutableArray array];
    NSMutableDictionary<SignalServiceAddress *, NSError *> *sendErrorPerRecipient = [NSMutableDictionary dictionary];

    [self unlockPreKeyUpdateFailuresPromise]
        .thenInBackground(^(id value) {
            return [self
                sendPromiseForRecipients:recipients
                                 message:message
                                  thread:thread
                       senderCertificate:senderCertificate
                          sendErrorBlock:^(SignalRecipient *recipient, NSError *error) {
                              @synchronized(sendErrors) {
                                  [sendErrors addObject:error];
                                  sendErrorPerRecipient[recipient.address] = error;
                              }
                          }];
        })
        .thenInBackground(^(id value) {
            successHandler();
        })
        .catchInBackground(^(id failure) {
            NSError *firstRetryableError = nil;
            NSError *firstNonRetryableError = nil;

            NSArray<NSError *> *sendErrorsCopy;
            NSDictionary<SignalServiceAddress *, NSError *> *sendErrorPerRecipientCopy;
            @synchronized(sendErrors) {
                sendErrorsCopy = [sendErrors copy];
                sendErrorPerRecipientCopy = [sendErrorPerRecipient copy];
            }

            // Record the individual error for each "failed" recipient.
            DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                for (SignalServiceAddress *address in sendErrorPerRecipientCopy) {
                    NSError *error = sendErrorPerRecipientCopy[address];

                    // Some errors should be ignored when sending messages
                    // to groups.  See discussion on
                    // NSError (OWSMessageSender) category.
                    if (isGroupSend && [error shouldBeIgnoredForGroups]) {
                        continue;
                    }

                    // We only want to record a failure for errors we can
                    // no longer retry.
                    if (error.isRetryable) {
                        continue;
                    }

                    [message updateWithFailedRecipient:address error:error transaction:transaction];
                }
            });

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
}

- (nullable TSThread *)threadForMessageWithSneakyTransaction:(TSMessage *)message
{
    OWSAssertDebug(!NSThread.isMainThread);

    // Try to avoid opening a write transaction.
    __block TSThread *_Nullable thread = nil;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        thread = [message threadWithTransaction:transaction];
    }];
    if (thread != nil) {
        return thread;
    }

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        thread = [self threadForMessage:message transaction:transaction];
    });
    return thread;
}

- (nullable TSThread *)threadForMessage:(TSMessage *)message transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(!NSThread.isMainThread);

    TSThread *_Nullable thread = [message threadWithTransaction:transaction];
    //    OWSAssertDebug(thread != nil);

    // For some legacy sync messages, thread may be nil.
    // In this case, we should try to use the "local" thread.
    BOOL isSyncMessage = [message isKindOfClass:[OWSOutgoingSyncMessage class]];
    if (thread == nil && isSyncMessage) {
        thread = [TSAccountManager getOrCreateLocalThreadWithTransaction:transaction];
        if (thread == nil) {
            OWSFailDebug(@"Could not restore thread for sync message.");
        } else {
            OWSLogInfo(@"Thread restored for sync message.");
        }
    }
    return thread;
}

- (void)unregisteredRecipient:(SignalRecipient *)recipient
                      message:(TSOutgoingMessage *)message
                       thread:(TSThread *)thread
{
    OWSAssertDebug(!NSThread.isMainThread);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        if (thread.isGroupThread) {
            // Mark as "skipped" group members who no longer have signal accounts.
            [message updateWithSkippedRecipient:recipient.address transaction:transaction];
        }

        if (![SignalRecipient isRegisteredRecipient:recipient.address transaction:transaction]) {
            return;
        }

        [SignalRecipient markRecipientAsUnregistered:recipient.address transaction:transaction];

        [[TSInfoMessage userNotRegisteredMessageInThread:thread
                                                 address:recipient.address] anyInsertWithTransaction:transaction];

        // TODO: Should we deleteAllSessionsForContact here?
        //       If so, we'll need to avoid doing a prekey fetch every
        //       time we try to send a message to an unregistered user.
    });
}

- (nullable NSArray<NSDictionary *> *)deviceMessagesForMessageSend:(OWSMessageSend *)messageSend
                                                             error:(NSError **)errorHandle
{
    OWSAssertDebug(!NSThread.isMainThread);
    OWSAssertDebug(messageSend);
    OWSAssertDebug(errorHandle);

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
                          [self.contactsManager displayNameForAddress:recipient.address]];
            NSError *error = OWSErrorMakeUntrustedIdentityError(localizedErrorDescription, recipient.address);

            // Key will continue to be unaccepted, so no need to retry. It'll only cause us to hit the Pre-Key request
            // rate limit.
            [error setIsRetryable:NO];
            // Avoid the "Too many failures with this contact" error rate limiting.
            [error setIsFatal:YES];
            *errorHandle = error;

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
        operationQueue.name = @"MessageSender.sendMessageToRecipient";
        operationQueue.maxConcurrentOperationCount = 6;
    });
    [operationQueue addOperationWithBlock:^{
        [self _sendMessageToRecipient:messageSend];
    }];
}

- (void)_sendMessageToRecipient:(OWSMessageSend *)messageSend
{
    OWSAssertDebug(!NSThread.isMainThread);
    OWSAssertDebug(messageSend);
    OWSAssertDebug(messageSend.thread);

    TSOutgoingMessage *message = messageSend.message;
    SignalRecipient *recipient = messageSend.recipient;

    OWSLogInfo(@"attempting to send message: %@, timestamp: %llu, recipient: %@",
        message.class,
        message.timestamp,
        recipient.address);

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
    NSArray<NSDictionary *> *_Nullable deviceMessages = [self deviceMessagesForMessageSend:messageSend
                                                                                     error:&deviceMessagesError];
    if (deviceMessagesError || !deviceMessages) {
        OWSAssertDebug(deviceMessagesError);
        return messageSend.failure(deviceMessagesError);
    }

    if (messageSend.isLocalAddress) {
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

        __block BOOL mayHaveLinkedDevices;
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            mayHaveLinkedDevices = [OWSDeviceManager.sharedManager mayHaveLinkedDevicesWithTransaction:transaction];
        }];

        BOOL hasDeviceMessages = NO;
        for (NSDictionary<NSString *, id> *deviceMessage in deviceMessages) {
            NSString *_Nullable destination = deviceMessage[@"destination"];
            if (!destination) {
                OWSFailDebug(@"Sync device message missing destination: %@", deviceMessage);
                continue;
            }

            SignalServiceAddress *destinationAddress;
            if ([[NSUUID alloc] initWithUUIDString:destination]) {
                destinationAddress = [[SignalServiceAddress alloc] initWithUuidString:destination];
            } else {
                destinationAddress = [[SignalServiceAddress alloc] initWithPhoneNumber:destination];
            }

            NSNumber *_Nullable destinationDeviceId = deviceMessage[@"destinationDeviceId"];
            if (!destinationDeviceId) {
                OWSFailDebug(@"Sync device message missing destination device id: %@", deviceMessage);
                continue;
            }
            if (destinationDeviceId.intValue != self.tsAccountManager.storedDeviceId) {
                hasDeviceMessages = YES;
                break;
            }
        }

        OWSLogInfo(@"mayHaveLinkedDevices: %d, hasDeviceMessages: %d", mayHaveLinkedDevices, hasDeviceMessages);

        if (!mayHaveLinkedDevices && !hasDeviceMessages) {
            OWSLogInfo(@"Ignoring sync message without secondary devices: %@", [message class]);
            OWSAssertDebug([message isKindOfClass:[OWSOutgoingSyncMessage class]]);

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
            return [OWSRequestFactory submitMessageRequestWithAddress:recipient.address
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
        address:recipient.address
        udAccess:messageSend.udSendingAccess.udAccess
        canFailoverUDAuth:NO];
    [requestMaker makeRequestObjc]
        .thenInBackground(^(OWSRequestMakerResult *result) {
            [self messageSendDidSucceed:messageSend
                         deviceMessages:deviceMessages
                            wasSentByUD:result.wasSentByUD
                     wasSentByWebsocket:result.wasSentByWebsocket];
        })
        .catchInBackground(^(NSError *error) {
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
                    responseData = underlyingError.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
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
}

- (void)messageSendDidSucceed:(OWSMessageSend *)messageSend
               deviceMessages:(NSArray<NSDictionary *> *)deviceMessages
                  wasSentByUD:(BOOL)wasSentByUD
           wasSentByWebsocket:(BOOL)wasSentByWebsocket
{
    OWSAssertDebug(!NSThread.isMainThread);
    OWSAssertDebug(messageSend);
    OWSAssertDebug(deviceMessages);

    SignalRecipient *recipient = messageSend.recipient;

    OWSLogInfo(@"successfully sent message: %@ timestamp: %llu, wasSentByUD: %d",
        messageSend.message.class,
        messageSend.message.timestamp,
        wasSentByUD);

    if (messageSend.isLocalAddress && deviceMessages.count == 0) {
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

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [messageSend.message updateWithSentRecipient:messageSend.recipient.address
                                         wasSentByUD:wasSentByUD
                                         transaction:transaction];

        // If we've just delivered a message to a user, we know they
        // have a valid Signal account.
        [SignalRecipient markRecipientAsRegisteredAndGet:recipient.address transaction:transaction];

        [self.profileManager didSendOrReceiveMessageFromAddress:recipient.address transaction:transaction];
    });

    messageSend.success();
}

- (void)messageSendDidFail:(OWSMessageSend *)messageSend
            deviceMessages:(NSArray<NSDictionary *> *)deviceMessages
                statusCode:(NSInteger)statusCode
                     error:(NSError *)responseError
              responseData:(nullable NSData *)responseData
{
    OWSAssertDebug(!NSThread.isMainThread);
    OWSAssertDebug(messageSend);
    OWSAssertDebug(messageSend.thread);
    OWSAssertDebug(deviceMessages);
    OWSAssertDebug(responseError);

    TSOutgoingMessage *message = messageSend.message;
    SignalRecipient *recipient = messageSend.recipient;

    OWSLogInfo(@"failed to send message: %@, timestamp: %llu, to recipient: %@",
        message.class,
        message.timestamp,
        recipient.address);

    void (^retrySend)(void) = ^void() {
        if (messageSend.remainingAttempts <= 0) {
            return messageSend.failure(responseError);
        }

        OWSLogDebug(@"Retrying: %@", message.debugDescription);
        [self sendMessageToRecipient:messageSend];
    };

    void (^handle404)(void) = ^{
        OWSLogWarn(@"Unregistered recipient: %@", recipient.address);

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            if (![messageSend.message isKindOfClass:[OWSOutgoingSyncMessage class]]) {
                TSThread *thread = messageSend.thread;
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
            OWSLogWarn(@"Mismatched devices for recipient: %@ (%zd)", recipient.address, deviceMessages.count);

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

            if (messageSend.isLocalAddress) {
                // Don't use websocket; it may have obsolete cached state.
                [messageSend setHasWebsocketSendFailed:YES];
            }

            break;
        }
        case 410: {
            // Stale devices
            OWSLogWarn(@"Stale devices for recipient: %@", recipient.address);

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

            [self handleStaleDevicesWithResponseJson:responseJson
                                    recipientAddress:recipient.address
                                          completion:retrySend];

            if (messageSend.isLocalAddress) {
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
    OWSAssertDebug(!NSThread.isMainThread);
    OWSAssertDebug(responseJson);
    OWSAssertDebug(recipient);
    OWSAssertDebug(completionHandler);

    NSArray *extraDevices = responseJson[@"extraDevices"];
    NSArray *missingDevices = responseJson[@"missingDevices"];

    if (missingDevices.count > 0) {
        if (recipient.address.isLocalAddress) {
            [OWSDeviceManager.sharedManager setMayHaveLinkedDevices];
        }
    }

    DatabaseStorageWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
        if (extraDevices.count < 1 && missingDevices.count < 1) {
            OWSProdFail([OWSAnalyticsEvents messageSenderErrorNoMissingOrExtraDevices]);
        }
        [recipient updateRegisteredRecipientWithDevicesToAdd:missingDevices
                                             devicesToRemove:extraDevices
                                                 transaction:transaction];

        if (extraDevices && extraDevices.count > 0) {
            OWSLogInfo(@"Deleting sessions for extra devices: %@", extraDevices);
            for (NSNumber *extraDeviceId in extraDevices) {
                [self.sessionStore deleteSessionForAddress:recipient.address
                                                  deviceId:extraDeviceId.intValue
                                               transaction:transaction];
            }
        }
    });
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        completionHandler();
    });
}

- (void)handleMessageSentLocally:(TSOutgoingMessage *)message
                         success:(void (^)(void))successParam
                         failure:(RetryableFailureHandler)failure
{
    OWSAssertDebug(!NSThread.isMainThread);

    dispatch_block_t success = ^{
        // This should not be nil, even for legacy queued messages.
        TSThread *_Nullable thread = [self threadForMessageWithSneakyTransaction:message];
        OWSAssertDebug(thread != nil);

        TSContactThread *_Nullable contactThread;
        if ([thread isKindOfClass:[TSContactThread class]]) {
            contactThread = (TSContactThread *)thread;
        }

        BOOL isSyncMessage = [message isKindOfClass:[OWSOutgoingSyncMessage class]];
        if (contactThread && contactThread.contactAddress.isLocalAddress && !isSyncMessage) {
            OWSAssertDebug(message.recipientAddresses.count == 1);
            // Don't mark self-sent messages as read (or sent) until the sync transcript is sent.
            DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                for (SignalServiceAddress *sendingAddress in message.sendingRecipientAddresses) {
                    [message updateWithReadRecipient:sendingAddress
                                       readTimestamp:message.timestamp
                                         transaction:transaction];
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

    BOOL shouldSendTranscript = (SSKFeatureFlags.sendRecipientUpdates || !message.hasSyncedTranscript);
    if (!shouldSendTranscript) {
        return success();
    }

    BOOL isRecipientUpdate = message.hasSyncedTranscript;
    [self sendSyncTranscriptForMessage:message
                     isRecipientUpdate:isRecipientUpdate
                               success:^{
                                   DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                                       [message updateWithHasSyncedTranscript:YES transaction:transaction];
                                   });

                                   success();
                               }
                               failure:failure];
}

- (void)sendSyncTranscriptForMessage:(TSOutgoingMessage *)message
                   isRecipientUpdate:(BOOL)isRecipientUpdate
                             success:(void (^)(void))success
                             failure:(RetryableFailureHandler)failure
{
    OWSAssertDebug(!NSThread.isMainThread);

    SignalServiceAddress *localAddress = self.tsAccountManager.localAddress;
    // After sending a message to its "message thread",
    // we send a sync transcript to the "local thread".
    __block TSThread *_Nullable localThread;
    __block TSThread *_Nullable messageThread;
    __block SignalRecipient *recipient;
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        localThread = [TSAccountManager getOrCreateLocalThreadWithTransaction:transaction];

        messageThread = [self threadForMessage:message transaction:transaction];

        recipient = [SignalRecipient markRecipientAsRegisteredAndGet:localAddress transaction:transaction];
    });
    if (localThread == nil) {
        return failure(OWSErrorMakeAssertionError(@"Missing local thread"));
    }
    if (messageThread == nil) {
        return failure(OWSErrorMakeAssertionError(@"Missing message thread"));
    }

    OWSOutgoingSentMessageTranscript *sentMessageTranscript =
        [[OWSOutgoingSentMessageTranscript alloc] initWithLocalThread:localThread
                                                        messageThread:messageThread
                                                      outgoingMessage:message
                                                    isRecipientUpdate:isRecipientUpdate];

    OWSMessageSend *messageSend = [[OWSMessageSend alloc] initWithMessage:sentMessageTranscript
                                                                   thread:localThread
                                                                recipient:recipient
                                                          udSendingAccess:nil
                                                             localAddress:localAddress
                                                           sendErrorBlock:nil];
    [self sendMessageToRecipient:messageSend];
    messageSend.asAnyPromise
        .thenInBackground(^{
            OWSLogInfo(@"Successfully sent sync transcript.");

            success();
        })
        .catchInBackground(^(NSError *error) {
            OWSLogInfo(@"Failed to send sync transcript: %@ (isRetryable: %d)", error, [error isRetryable]);

            failure(error);
        });
}

- (NSArray<NSDictionary *> *)throws_deviceMessagesForMessageSend:(OWSMessageSend *)messageSend
{
    OWSAssertDebug(!NSThread.isMainThread);
    OWSAssertDebug(messageSend.message);
    OWSAssertDebug(messageSend.recipient);

    SignalRecipient *recipient = messageSend.recipient;

    NSMutableArray *messagesArray = [NSMutableArray arrayWithCapacity:recipient.devices.count];

    __block NSData *_Nullable plainText;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        plainText = [messageSend.message buildPlainTextData:messageSend.recipient
                                                     thread:messageSend.thread
                                                transaction:transaction];
    }];

    if (!plainText) {
        OWSRaiseException(InvalidMessageException, @"Failed to build message proto");
    }
    OWSLogDebug(
        @"built message: %@ plainTextData.length: %lu", [messageSend.message class], (unsigned long)plainText.length);

    OWSLogVerbose(@"building device messages for: %@ %@ (isLocalAddress: %d, isUDSend: %d)",
        recipient.address,
        recipient.devices,
        messageSend.isLocalAddress,
        messageSend.isUDSend);

    NSMutableArray<NSNumber *> *deviceIds = [messageSend.deviceIds mutableCopy];
    OWSAssertDebug(deviceIds);

    if (messageSend.isLocalAddress) {
        [deviceIds removeObject:@(self.tsAccountManager.storedDeviceId)];
    }

    for (NSNumber *deviceId in deviceIds) {
        @try {
            // This may involve blocking network requests.
            [self throws_ensureRecipientHasSessionForMessageSend:messageSend deviceId:deviceId];
        } @catch (NSException *exception) {
            if ([exception.name isEqualToString:OWSMessageSenderInvalidDeviceException]) {
                DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                    [recipient updateRegisteredRecipientWithDevicesToAdd:nil
                                                         devicesToRemove:@[ deviceId ]
                                                             transaction:transaction];
                });
                [messageSend removeDeviceId:deviceId];
                [deviceIds removeObject:deviceId];
            } else {
                @throw exception;
            }
        }
    }

    __block NSException *encryptionException;
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        for (NSNumber *deviceId in deviceIds) {
            @try {
                NSDictionary *_Nullable messageDict = [self throws_encryptedMessageForMessageSend:messageSend
                                                                                         deviceId:deviceId
                                                                                        plainText:plainText
                                                                                      transaction:transaction];
                if (messageDict) {
                    [messagesArray addObject:messageDict];
                } else {
                    OWSRaiseException(InvalidMessageException, @"Failed to encrypt message");
                }
            } @catch (NSException *exception) {
                encryptionException = exception;
                return;
            }
        }
    });
    if (encryptionException) {
        OWSLogInfo(@"Exception during encryption: %@", encryptionException);
        @throw encryptionException;
    }
    return [messagesArray copy];
}

- (void)throws_ensureRecipientHasSessionForMessageSend:(OWSMessageSend *)messageSend deviceId:(NSNumber *)deviceId
{
    OWSAssertDebug(!NSThread.isMainThread);
    OWSAssertDebug(messageSend);
    OWSAssertDebug(messageSend.recipient);
    OWSAssertDebug(deviceId);

    SignalServiceAddress *recipientAddress = messageSend.recipient.address;
    OWSAssertDebug(recipientAddress.isValid);

    NSString *accountId = messageSend.recipient.accountId;

    __block BOOL hasSession;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        hasSession = [self.sessionStore containsSessionForAccountId:accountId
                                                           deviceId:[deviceId intValue]
                                                        transaction:transaction];
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
    [MessageSending makePrekeyRequestWithMessageSend:messageSend
        deviceId:deviceId
        success:^(PreKeyBundle *_Nullable responseBundle) {
            bundle = responseBundle;
            dispatch_semaphore_signal(sema);
        }
        failure:^(NSError *error) {
            NSNumber *_Nullable statusCode = HTTPStatusCodeForError(error);
            OWSLogVerbose(@"statusCode: %@", statusCode);
            if ([MessageSending isMissingDeviceError:error]) {
                // Can't throw exception from within callback as it's probabably a different thread.
                exception = [NSException exceptionWithName:OWSMessageSenderInvalidDeviceException
                                                    reason:@"Device not registered"
                                                  userInfo:nil];
            } else if ([MessageSending isPrekeyRateLimitError:error]) {
                // Can't throw exception from within callback as it's probabably a different thread.
                exception = [NSException exceptionWithName:OWSMessageSenderRateLimitedException
                                                    reason:@"Too many prekey requests"
                                                  userInfo:nil];
            } else if ([MessageSending isUntrustedIdentityError:error]) {
                // Can't throw exception from within callback as it's probabably a different thread.
                exception = [NSException exceptionWithName:UntrustedIdentityKeyException
                                                    reason:@"Identity key is not valid"
                                                  userInfo:@ {}];
            } else if (IsNetworkConnectivityFailure(error)) {
                OWSLogWarn(@"Network failure in prekey request.");
            } else {
                OWSFailDebug(@"Error: %@", error);
            }
            dispatch_semaphore_signal(sema);
        }];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    if (exception) {
        OWSLogVerbose(@"exception: %@", exception);
        @throw exception;
    }

    if (!bundle) {
        NSString *missingPrekeyBundleException = @"missingPrekeyBundleException";
        OWSRaiseException(
            missingPrekeyBundleException, @"Can't get a prekey bundle from the server with required information");
    } else {
        [self throws_createSessionForPreKeyBundle:bundle
                                        accountId:accountId
                                 recipientAddress:recipientAddress
                                         deviceId:deviceId];
    }
}

- (void)throws_createSessionForPreKeyBundle:(PreKeyBundle *)bundle
                                  accountId:(NSString *)accountId
                           recipientAddress:(SignalServiceAddress *)recipientAddress
                                   deviceId:(NSNumber *)deviceId
{
    OWSAssertDebug(!NSThread.isMainThread);

    SessionBuilder *builder = [[SessionBuilder alloc] initWithSessionStore:self.sessionStore
                                                               preKeyStore:self.preKeyStore
                                                         signedPreKeyStore:self.signedPreKeyStore
                                                          identityKeyStore:self.identityManager
                                                               recipientId:accountId
                                                                  deviceId:[deviceId intValue]];
    __block NSException *_Nullable exception;
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        if ([self.sessionStore containsSessionForAccountId:accountId
                                                  deviceId:[deviceId intValue]
                                               transaction:transaction]) {
            OWSLogWarn(@"Session already exists.");
            return;
        }

        @try {
            [builder throws_processPrekeyBundle:bundle protocolContext:transaction];

            if (![self.sessionStore containsSessionForAccountId:accountId
                                                       deviceId:[deviceId intValue]
                                                    transaction:transaction]) {
                OWSFailDebug(@"Session does not exist.");
            }
        } @catch (NSException *caughtException) {
            exception = caughtException;

            if ([exception.name isEqualToString:UntrustedIdentityKeyException]) {
                [MessageSending handleUntrustedIdentityKeyErrorWithAccountId:accountId
                                                            recipientAddress:recipientAddress
                                                                preKeyBundle:bundle
                                                                 transaction:transaction];
            }
        }
    });
    if (exception) {
        @throw exception;
    }
}

- (nullable NSDictionary *)throws_encryptedMessageForMessageSend:(OWSMessageSend *)messageSend
                                                        deviceId:(NSNumber *)deviceId
                                                       plainText:(NSData *)plainText
                                                     transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(!NSThread.isMainThread);
    OWSAssertDebug(messageSend);
    OWSAssertDebug(messageSend.recipient);
    OWSAssertDebug(deviceId);
    OWSAssertDebug(plainText);
    OWSAssertDebug(transaction);

    TSOutgoingMessage *message = messageSend.message;
    SignalServiceAddress *recipientAddress = messageSend.recipient.address;
    OWSAssertDebug(recipientAddress.isValid);

    if (![self.sessionStore containsSessionForAddress:recipientAddress
                                             deviceId:[deviceId intValue]
                                          transaction:transaction]) {
        NSString *missingSessionException = @"missingSessionException";
        OWSRaiseException(missingSessionException,
            @"Unexpectedly missing session for recipientAddress: %@, device: %@",
            recipientAddress,
            deviceId);
    }

    SessionCipher *cipher = [[SessionCipher alloc] initWithSessionStore:self.sessionStore
                                                            preKeyStore:self.preKeyStore
                                                      signedPreKeyStore:self.signedPreKeyStore
                                                       identityKeyStore:self.identityManager
                                                            recipientId:messageSend.recipient.accountId
                                                               deviceId:[deviceId intValue]];

    NSData *_Nullable serializedMessage;
    TSWhisperMessageType messageType;
    OWSUDSendingAccess *_Nullable udSendingAcess = messageSend.udSendingAccess;
    if (udSendingAcess != nil) {
        NSError *error;
        SMKSecretSessionCipher *_Nullable secretCipher =
            [[SMKSecretSessionCipher alloc] initWithSessionStore:self.sessionStore
                                                     preKeyStore:self.preKeyStore
                                               signedPreKeyStore:self.signedPreKeyStore
                                                   identityStore:self.identityManager
                                                           error:&error];
        if (error || !secretCipher) {
            OWSRaiseException(@"SecretSessionCipherFailure", @"Can't create secret session cipher.");
        }
        serializedMessage = [secretCipher throwswrapped_encryptMessageWithRecipientId:messageSend.recipient.accountId
                                                                             deviceId:deviceId.intValue
                                                                      paddedPlaintext:[plainText paddedMessageBody]
                                                                    senderCertificate:udSendingAcess.senderCertificate
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
        id<CipherMessage> encryptedMessage = [cipher throws_encryptMessage:[plainText paddedMessageBody]
                                                           protocolContext:transaction];
        serializedMessage = encryptedMessage.serialized;
        messageType = [self messageTypeForCipherMessage:encryptedMessage];
    }

    BOOL isSilent = message.isSilent;
    BOOL isOnline = message.isOnline;
    OWSMessageServiceParams *messageParams =
        [[OWSMessageServiceParams alloc] initWithType:messageType
                                              address:recipientAddress
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

// Called when the server indicates that the devices no longer exist - e.g. when the remote recipient has reinstalled.
- (void)handleStaleDevicesWithResponseJson:(NSDictionary *)responseJson
                          recipientAddress:(SignalServiceAddress *)address
                                completion:(void (^)(void))completionHandler
{
    OWSAssertDebug(!NSThread.isMainThread);
    NSArray *devices = responseJson[@"staleDevices"];

    if (!([devices count] > 0)) {
        return completionHandler();
    }

    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        for (NSUInteger i = 0; i < [devices count]; i++) {
            int deviceNumber = [devices[i] intValue];
            [self.sessionStore deleteSessionForAddress:address deviceId:deviceNumber transaction:transaction];
        }

        [transaction addAsyncCompletionOffMain:completionHandler];
    });
}

+ (NSOperationQueuePriority)queuePriorityForMessage:(TSOutgoingMessage *)message
{
    return message.hasRenderableContent ? NSOperationQueuePriorityHigh : NSOperationQueuePriorityNormal;
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

    if (message.quotedMessage) {
        // We need to update the message record here to reflect the new attachments we may create.
        [message
            anyUpdateOutgoingMessageWithTransaction:transaction
                                              block:^(TSOutgoingMessage *message) {
                                                  // Though we currently only ever expect at most one thumbnail, the
                                                  // proto data model suggests this could change. The logic is intended
                                                  // to work with multiple, but if we ever actually want to send
                                                  // multiple, we should do more testing.
                                                  NSArray<TSAttachmentStream *> *quotedThumbnailAttachments =
                                                      [message.quotedMessage
                                                          createThumbnailAttachmentsIfNecessaryWithTransaction:
                                                              transaction];
                                                  for (TSAttachmentStream *attachment in quotedThumbnailAttachments) {
                                                      [attachmentIds addObject:attachment.uniqueId];
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
        TSAttachmentStream *attachmentStream =
            [attachmentInfo asStreamConsumingDataSourceWithIsVoiceMessage:outgoingMessage.isVoiceMessage error:error];
        if (*error != nil) {
            return NO;
        }
        OWSAssert(attachmentStream != nil);
        [attachmentStreams addObject:attachmentStream];
    }

    [outgoingMessage
        anyUpdateOutgoingMessageWithTransaction:transaction
                                          block:^(TSOutgoingMessage *outgoingMessage) {
                                              NSMutableArray<NSString *> *attachmentIds =
                                                  [outgoingMessage.attachmentIds mutableCopy];
                                              for (TSAttachmentStream *attachmentStream in attachmentStreams) {
                                                  [attachmentIds addObject:attachmentStream.uniqueId];
                                              }
                                              outgoingMessage.attachmentIds = [attachmentIds copy];
                                          }];

    for (TSAttachmentStream *attachmentStream in attachmentStreams) {
        [attachmentStream anyInsertWithTransaction:transaction];
    }

    return YES;
}

@end

NS_ASSUME_NONNULL_END
