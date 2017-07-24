//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSMessagesManager.h"
#import "ContactsManagerProtocol.h"
#import "ContactsUpdater.h"
#import "MimeTypeUtil.h"
#import "NSData+messagePadding.h"
#import "NSDate+millisecondTimeStamp.h"
#import "NotificationsProtocol.h"
#import "OWSAttachmentsProcessor.h"
#import "OWSBlockingManager.h"
#import "OWSCallMessageHandler.h"
#import "OWSDisappearingConfigurationUpdateInfoMessage.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSError.h"
#import "OWSIncomingMessageFinder.h"
#import "OWSIncomingSentMessageTranscript.h"
#import "OWSMessageSender.h"
#import "OWSReadReceiptsProcessor.h"
#import "OWSRecordTranscriptJob.h"
#import "OWSSyncContactsMessage.h"
#import "OWSSyncGroupsMessage.h"
#import "OWSSyncGroupsRequestMessage.h"
#import "TSAccountManager.h"
#import "TSAttachmentStream.h"
#import "TSCall.h"
#import "TSContactThread.h"
#import "TSDatabaseView.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import "TSInfoMessage.h"
#import "TSInvalidIdentityKeyReceivingErrorMessage.h"
#import "TSNetworkManager.h"
#import "TSPreKeyManager.h"
#import "TSStorageHeaders.h"
#import "TextSecureKitEnv.h"
#import <AxolotlKit/AxolotlExceptions.h>
#import <AxolotlKit/SessionCipher.h>

NS_ASSUME_NONNULL_BEGIN

#define kOWSAnalyticsParameterEnvelopeIsLegacy @"envelope_is_legacy"
#define kOWSAnalyticsParameterEnvelopeHasContent @"has_content"
#define kOWSAnalyticsParameterEnvelopeType @"envelope_type"
#define kOWSAnalyticsParameterEnvelopeEncryptedLength @"encrypted_length"

#define AnalyticsParametersFromEnvelope(__envelope)                                                                    \
    ^{                                                                                                                 \
        NSData *__encryptedData = __envelope.hasContent ? __envelope.content : __envelope.legacyMessage;               \
        return (@{                                                                                                     \
            kOWSAnalyticsParameterEnvelopeIsLegacy : @(__envelope.hasLegacyMessage),                                   \
            kOWSAnalyticsParameterEnvelopeHasContent : @(__envelope.hasContent),                                       \
            kOWSAnalyticsParameterEnvelopeType : [self descriptionForEnvelopeType:__envelope],                         \
            kOWSAnalyticsParameterEnvelopeEncryptedLength : @(__encryptedData.length),                                 \
        });                                                                                                            \
    }

// The debug logs can be more verbose than the analytics events.
//
// In this case `descriptionForEnvelope` is valuable enough to
// log but too dangerous to include in the analytics event.
#define OWSProdErrorWEnvelope(__analyticsEventName, __envelope)                                                        \
    {                                                                                                                  \
        DDLogError(@"%s:%d %@: %@",                                                                                    \
            __PRETTY_FUNCTION__,                                                                                       \
            __LINE__,                                                                                                  \
            __analyticsEventName,                                                                                      \
            [self descriptionForEnvelope:__envelope]);                                                                 \
        OWSProdErrorWParams(__analyticsEventName, AnalyticsParametersFromEnvelope(__envelope))                         \
    }

@interface TSMessagesManager ()

@property (nonatomic, readonly) id<OWSCallMessageHandler> callMessageHandler;
@property (nonatomic, readonly) id<ContactsManagerProtocol> contactsManager;
@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) OWSIncomingMessageFinder *incomingMessageFinder;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
@property (nonatomic, readonly) OWSIdentityManager *identityManager;

@end

#pragma mark -

@implementation TSMessagesManager

+ (instancetype)sharedManager {
    static TSMessagesManager *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] initDefault];
    });
    return sharedMyManager;
}

- (instancetype)initDefault
{
    TSNetworkManager *networkManager = [TSNetworkManager sharedManager];
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    id<ContactsManagerProtocol> contactsManager = [TextSecureKitEnv sharedEnv].contactsManager;
    id<OWSCallMessageHandler> callMessageHandler = [TextSecureKitEnv sharedEnv].callMessageHandler;
    ContactsUpdater *contactsUpdater = [ContactsUpdater sharedUpdater];
    OWSIdentityManager *identityManager = [OWSIdentityManager sharedManager];
    OWSMessageSender *messageSender = [TextSecureKitEnv sharedEnv].messageSender;
    

    return [self initWithNetworkManager:networkManager
                         storageManager:storageManager
                     callMessageHandler:callMessageHandler
                        contactsManager:contactsManager
                        contactsUpdater:contactsUpdater
                        identityManager:identityManager
                          messageSender:messageSender];
}

- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager
                        storageManager:(TSStorageManager *)storageManager
                    callMessageHandler:(id<OWSCallMessageHandler>)callMessageHandler
                       contactsManager:(id<ContactsManagerProtocol>)contactsManager
                       contactsUpdater:(ContactsUpdater *)contactsUpdater
                       identityManager:(OWSIdentityManager *)identityManager
                         messageSender:(OWSMessageSender *)messageSender
{
    self = [super init];

    if (!self) {
        return self;
    }

    _storageManager = storageManager;
    _networkManager = networkManager;
    _callMessageHandler = callMessageHandler;
    _contactsManager = contactsManager;
    _contactsUpdater = contactsUpdater;
    _identityManager = identityManager;
    _messageSender = messageSender;

    _dbConnection = storageManager.newDatabaseConnection;
    _incomingMessageFinder = [[OWSIncomingMessageFinder alloc] initWithDatabase:storageManager.database];
    _blockingManager = [OWSBlockingManager sharedManager];

    OWSSingletonAssert();

    [self startObserving];

    return self;
}

- (void)startObserving
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModified:)
                                                 name:YapDatabaseModifiedNotification
                                               object:nil];
}

- (void)yapDatabaseModified:(NSNotification *)notification
{
    [self updateApplicationBadgeCount];
}

#pragma mark - Debugging

- (NSString *)descriptionForEnvelopeType:(OWSSignalServiceProtosEnvelope *)envelope
{
    OWSAssert(envelope != nil);

    switch (envelope.type) {
        case OWSSignalServiceProtosEnvelopeTypeReceipt:
            return @"DeliveryReceipt";
        case OWSSignalServiceProtosEnvelopeTypeUnknown:
            // Shouldn't happen
            OWSProdFail(@"message_manager_error_envelope_type_unknown");
            return @"Unknown";
        case OWSSignalServiceProtosEnvelopeTypeCiphertext:
            return @"SignalEncryptedMessage";
        case OWSSignalServiceProtosEnvelopeTypeKeyExchange:
            // Unsupported
            OWSProdFail(@"message_manager_error_envelope_type_key_exchange");
            return @"KeyExchange";
        case OWSSignalServiceProtosEnvelopeTypePrekeyBundle:
            return @"PreKeyEncryptedMessage";
        default:
            // Shouldn't happen
            OWSProdFail(@"message_manager_error_envelope_type_other");
            return @"Other";
    }
}

- (NSString *)descriptionForEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
{
    OWSAssert(envelope != nil);

    return [NSString stringWithFormat:@"<Envelope type: %@, source: %@.%d, timestamp: %llu content.length: %lu />",
                     [self descriptionForEnvelopeType:envelope],
                     envelope.source,
                     (unsigned int)envelope.sourceDevice,
                     envelope.timestamp,
                     (unsigned long)envelope.content.length];
}

/**
 * We don't want to just log `content.description` because we'd potentially log message bodies for dataMesssages and
 * sync transcripts
 */
- (NSString *)descriptionForContent:(OWSSignalServiceProtosContent *)content
{
    if (content.hasSyncMessage) {
        return [NSString stringWithFormat:@"<SyncMessage: %@ />", [self descriptionForSyncMessage:content.syncMessage]];
    } else if (content.hasDataMessage) {
        return [NSString stringWithFormat:@"<DataMessage: %@ />", [self descriptionForDataMessage:content.dataMessage]];
    } else if (content.hasCallMessage) {
        return [NSString stringWithFormat:@"<CallMessage: %@ />", content.callMessage];
    } else if (content.hasNullMessage) {
        return [NSString stringWithFormat:@"<NullMessage: %@ />", content.nullMessage];
    } else {
        // Don't fire an analytics event; if we ever add a new content type, we'd generate a ton of
        // analytics traffic.
        OWSFail(@"Unknown content type.");
        return @"UnknownContent";
    }
}

/**
 * We don't want to just log `dataMessage.description` because we'd potentially log message contents
 */
- (NSString *)descriptionForDataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
{
    NSMutableString *description = [NSMutableString new];

    if (dataMessage.hasGroup) {
        [description appendString:@"GroupDataMessage: "];
    } else {
        [description appendString:@"DataMessage: "];
    }

    if ((dataMessage.flags & OWSSignalServiceProtosDataMessageFlagsEndSession) != 0) {
        [description appendString:@"EndSession"];
    } else if ((dataMessage.flags & OWSSignalServiceProtosDataMessageFlagsExpirationTimerUpdate) != 0) {
        [description appendString:@"ExpirationTimerUpdate"];
    } else if (dataMessage.attachments.count > 0) {
        [description appendString:@"MessageWithAttachment"];
    } else {
        [description appendString:@"Plain"];
    }

    return [NSString stringWithFormat:@"<%@ />", description];
}

/**
 * We don't want to just log `syncMessage.description` because we'd potentially log message contents in sent transcripts
 */
- (NSString *)descriptionForSyncMessage:(OWSSignalServiceProtosSyncMessage *)syncMessage
{
    NSMutableString *description = [NSMutableString new];
    if (syncMessage.hasSent) {
        [description appendString:@"SentTranscript"];
    } else if (syncMessage.hasRequest) {
        if (syncMessage.request.type == OWSSignalServiceProtosSyncMessageRequestTypeContacts) {
            [description appendString:@"ContactRequest"];
        } else if (syncMessage.request.type == OWSSignalServiceProtosSyncMessageRequestTypeGroups) {
            [description appendString:@"GroupRequest"];
        } else if (syncMessage.request.type == OWSSignalServiceProtosSyncMessageRequestTypeBlocked) {
            [description appendString:@"BlockedRequest"];
        } else {
            // Shouldn't happen
            OWSFail(@"Unknown sync message request type");
            [description appendString:@"UnknownRequest"];
        }
    } else if (syncMessage.hasBlocked) {
        [description appendString:@"Blocked"];
    } else if (syncMessage.read.count > 0) {
        [description appendString:@"ReadReceipt"];
    } else if (syncMessage.hasVerified) {
        NSString *verifiedString =
            [NSString stringWithFormat:@"Verification for: %@", syncMessage.verified.destination];
        [description appendString:verifiedString];
    } else {
        // Shouldn't happen
        OWSFail(@"Unknown sync message type");
        [description appendString:@"Unknown"];
    }

    return description;
}

#pragma mark - message handling

- (void)processEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
             completion:(nullable MessageManagerCompletionBlock)completionHandler
{
    OWSAssert([NSThread isMainThread]);

    // Ensure that completionHandler is called on the main thread,
    // and handle the nil case.
    MessageManagerCompletionBlock completion = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionHandler) {
                completionHandler();
            }
        });
    };

    DDLogInfo(@"%@ received envelope: %@", self.tag, [self descriptionForEnvelope:envelope]);

    OWSAssert(envelope.source.length > 0);
    BOOL isEnvelopeBlocked = [_blockingManager.blockedPhoneNumbers containsObject:envelope.source];
    if (isEnvelopeBlocked) {
        DDLogInfo(@"%@ ignoring blocked envelope: %@", self.tag, envelope.source);
        completion();
        return;
    }

    @try {
        switch (envelope.type) {
            case OWSSignalServiceProtosEnvelopeTypeCiphertext: {
                [self handleSecureMessageAsync:envelope
                                    completion:^(NSError *_Nullable error) {
                                        DDLogDebug(@"%@ handled secure message.", self.tag);
                                        if (error) {
                                            DDLogError(
                                                @"%@ handling secure message from address: %@.%d failed with error: %@",
                                                self.tag,
                                                envelope.source,
                                                (unsigned int)envelope.sourceDevice,
                                                error);
                                            OWSProdError(@"message_manager_error_could_not_handle_secure_message");
                                        }
                                        completion();
                                    }];
                // Return to avoid double-acknowledging.
                return;
            }
            case OWSSignalServiceProtosEnvelopeTypePrekeyBundle: {
                [self handlePreKeyBundleAsync:envelope
                                   completion:^(NSError *_Nullable error) {
                                       DDLogDebug(@"%@ handled pre-key whisper message", self.tag);
                                       if (error) {
                                           DDLogError(@"%@ handling pre-key whisper message from address: %@.%d failed "
                                                      @"with error: %@",
                                               self.tag,
                                               envelope.source,
                                               (unsigned int)envelope.sourceDevice,
                                               error);
                                           OWSProdError(@"message_manager_error_could_not_handle_prekey_bundle");
                                       }
                                       completion();
                                   }];
                // Return to avoid double-acknowledging.
                return;
            }
            case OWSSignalServiceProtosEnvelopeTypeReceipt:
                [self handleDeliveryReceipt:envelope];
                break;

            // Other messages are just dismissed for now.

            case OWSSignalServiceProtosEnvelopeTypeKeyExchange:
                DDLogWarn(@"Received Key Exchange Message, not supported");
                break;
            case OWSSignalServiceProtosEnvelopeTypeUnknown:
                DDLogWarn(@"Received an unknown message type");
                break;
            default:
                DDLogWarn(@"Received unhandled envelope type: %d", (int)envelope.type);
                break;
        }
    } @catch (NSException *exception) {
        DDLogError(@"Received an incorrectly formatted protocol buffer: %@", exception.debugDescription);
        OWSProdFailWNSException(@"message_manager_error_invalid_protocol_message", exception);
    }

    completion();
}

- (void)handleDeliveryReceipt:(OWSSignalServiceProtosEnvelope *)envelope
{
    OWSAssert([NSThread isMainThread]);
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSInteraction *interaction =
            [TSInteraction interactionForTimestamp:envelope.timestamp withTransaction:transaction];
        if ([interaction isKindOfClass:[TSOutgoingMessage class]]) {
            TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)interaction;
            [outgoingMessage updateWithWasDeliveredWithTransaction:transaction];
        }
    }];
}

- (void)handleSecureMessageAsync:(OWSSignalServiceProtosEnvelope *)messageEnvelope
                      completion:(void (^)(NSError *_Nullable error))completion
{
    OWSAssert([NSThread isMainThread]);
    @synchronized(self) {
        TSStorageManager *storageManager = [TSStorageManager sharedManager];
        NSString *recipientId = messageEnvelope.source;
        int deviceId = messageEnvelope.sourceDevice;
        dispatch_async([OWSDispatch sessionStoreQueue], ^{
            // DEPRECATED - Remove after all clients have been upgraded.
            NSData *encryptedData
                = messageEnvelope.hasContent ? messageEnvelope.content : messageEnvelope.legacyMessage;
            if (!encryptedData) {
                OWSProdFail(@"message_manager_error_message_envelope_has_no_content");
                completion(nil);
                return;
            }

            NSUInteger kMaxEncryptedDataLength = 250 * 1024;
            if (encryptedData.length > kMaxEncryptedDataLength) {
                OWSProdErrorWParams(@"message_manager_error_oversize_message", ^{
                    return (@{
                        @"message_size" : @([OWSAnalytics orderOfMagnitudeOf:(long)encryptedData.length]),
                    });
                });
                completion(nil);
                return;
            }

            NSData *plaintextData;

            @try {
                WhisperMessage *message = [[WhisperMessage alloc] initWithData:encryptedData];
                SessionCipher *cipher = [[SessionCipher alloc] initWithSessionStore:storageManager
                                                                        preKeyStore:storageManager
                                                                  signedPreKeyStore:storageManager
                                                                   identityKeyStore:self.identityManager
                                                                        recipientId:recipientId
                                                                           deviceId:deviceId];

                plaintextData = [[cipher decrypt:message] removePadding];
            } @catch (NSException *exception) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self processException:exception envelope:messageEnvelope];
                    NSString *errorDescription =
                        [NSString stringWithFormat:@"Exception while decrypting: %@", exception.description];
                    NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptMessage, errorDescription);
                    completion(error);
                });
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [self handleEnvelope:messageEnvelope plaintextData:plaintextData];
                completion(nil);
            });
        });
    }
}

- (void)handlePreKeyBundleAsync:(OWSSignalServiceProtosEnvelope *)preKeyEnvelope
                     completion:(void (^)(NSError *_Nullable error))completion
{
    OWSAssert([NSThread isMainThread]);

    @synchronized(self) {
        TSStorageManager *storageManager = [TSStorageManager sharedManager];
        NSString *recipientId = preKeyEnvelope.source;
        int deviceId = preKeyEnvelope.sourceDevice;

        // DEPRECATED - Remove after all clients have been upgraded.
        NSData *encryptedData = preKeyEnvelope.hasContent ? preKeyEnvelope.content : preKeyEnvelope.legacyMessage;
        if (!encryptedData) {
            OWSProdFail(@"message_manager_error_prekey_bundle_envelope_has_no_content");
            completion(nil);
            return;
        }

        dispatch_async([OWSDispatch sessionStoreQueue], ^{
            NSData *plaintextData;
            @try {
                // Check whether we need to refresh our PreKeys every time we receive a PreKeyWhisperMessage.
                [TSPreKeyManager checkPreKeys];

                PreKeyWhisperMessage *message = [[PreKeyWhisperMessage alloc] initWithData:encryptedData];
                SessionCipher *cipher = [[SessionCipher alloc] initWithSessionStore:storageManager
                                                                        preKeyStore:storageManager
                                                                  signedPreKeyStore:storageManager
                                                                   identityKeyStore:self.identityManager
                                                                        recipientId:recipientId
                                                                           deviceId:deviceId];

                plaintextData = [[cipher decrypt:message] removePadding];
            } @catch (NSException *exception) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self processException:exception envelope:preKeyEnvelope];
                    NSString *errorDescription = [NSString stringWithFormat:@"Exception while decrypting PreKey Bundle: %@", exception.description];
                    NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecryptMessage, errorDescription);
                    completion(error);
                });
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [self handleEnvelope:preKeyEnvelope plaintextData:plaintextData];
                completion(nil);
            });
        });
    }
}

- (void)handleEnvelope:(OWSSignalServiceProtosEnvelope *)envelope plaintextData:(NSData *)plaintextData
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(envelope.hasTimestamp && envelope.timestamp > 0);
    OWSAssert(envelope.hasSource && envelope.source.length > 0);
    OWSAssert(envelope.hasSourceDevice && envelope.sourceDevice > 0);

    BOOL duplicateEnvelope = [self.incomingMessageFinder existsMessageWithTimestamp:envelope.timestamp
                                                                           sourceId:envelope.source
                                                                     sourceDeviceId:envelope.sourceDevice];
    if (duplicateEnvelope) {
        DDLogInfo(@"%@ Ignoring previously received envelope from %@.%d with timestamp: %llu", self.tag, envelope.source, (unsigned int)envelope.sourceDevice, envelope.timestamp);
        return;
    }

    if (envelope.hasContent) {
        OWSSignalServiceProtosContent *content = [OWSSignalServiceProtosContent parseFromData:plaintextData];
        DDLogInfo(@"%@ handling content: <Content: %@>", self.tag, [self descriptionForContent:content]);
        if (content.hasSyncMessage) {
            [self handleIncomingEnvelope:envelope withSyncMessage:content.syncMessage];
        } else if (content.hasDataMessage) {
            [self handleIncomingEnvelope:envelope withDataMessage:content.dataMessage];
        } else if (content.hasCallMessage) {
            [self handleIncomingEnvelope:envelope withCallMessage:content.callMessage];
        } else if (content.hasNullMessage) {
            DDLogInfo(@"%@ Received null message.", self.tag);
        } else {
            DDLogWarn(@"%@ Ignoring envelope. Content with no known payload", self.tag);
        }
    } else if (envelope.hasLegacyMessage) { // DEPRECATED - Remove after all clients have been upgraded.
        OWSSignalServiceProtosDataMessage *dataMessage =
            [OWSSignalServiceProtosDataMessage parseFromData:plaintextData];
        DDLogInfo(@"%@ handling dataMessage: %@", self.tag, [self descriptionForDataMessage:dataMessage]);
        [self handleIncomingEnvelope:envelope withDataMessage:dataMessage];
    } else {
        DDLogWarn(@"%@ Ignoring envelope with neither DataMessage nor Content.", self.tag);
    }
}

- (void)handleIncomingEnvelope:(OWSSignalServiceProtosEnvelope *)incomingEnvelope
               withDataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
{
    OWSAssert([NSThread isMainThread]);

    if (dataMessage.hasGroup) {
        __block BOOL ignoreMessage = NO;
        [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            TSGroupModel *emptyModelToFillOutId =
                [[TSGroupModel alloc] initWithTitle:nil memberIds:nil image:nil groupId:dataMessage.group.id];
            TSGroupThread *gThread = [TSGroupThread threadWithGroupModel:emptyModelToFillOutId transaction:transaction];
            if (gThread == nil && dataMessage.group.type != OWSSignalServiceProtosGroupContextTypeUpdate) {
                ignoreMessage = YES;
            }
        }];
        if (ignoreMessage) {
            // FIXME: https://github.com/WhisperSystems/Signal-iOS/issues/1340
            DDLogInfo(@"%@ Received message from group that I left or don't know about from: %@.",
                self.tag,
                incomingEnvelope.source);

            NSString *recipientId = incomingEnvelope.source;

            __block TSThread *thread;
            [[TSStorageManager sharedManager].dbReadWriteConnection
                readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    thread = [TSContactThread getOrCreateThreadWithContactId:recipientId transaction:transaction];
                }];

            NSData *groupId = dataMessage.group.id;
            OWSAssert(groupId);
            OWSSyncGroupsRequestMessage *syncGroupsRequestMessage =
                [[OWSSyncGroupsRequestMessage alloc] initWithThread:thread groupId:groupId];
            [self.messageSender sendMessage:syncGroupsRequestMessage
                success:^{
                    DDLogWarn(@"%@ Successfully sent Request Group Info message.", self.tag);
                }
                failure:^(NSError *error) {
                    DDLogError(@"%@ Failed to send Request Group Info message with error: %@", self.tag, error);
                }];

            return;
        }
    }
    if ((dataMessage.flags & OWSSignalServiceProtosDataMessageFlagsEndSession) != 0) {
        [self handleEndSessionMessageWithEnvelope:incomingEnvelope dataMessage:dataMessage];
    } else if ((dataMessage.flags & OWSSignalServiceProtosDataMessageFlagsExpirationTimerUpdate) != 0) {
        [self handleExpirationTimerUpdateMessageWithEnvelope:incomingEnvelope dataMessage:dataMessage];
    } else if (dataMessage.attachments.count > 0) {
        [self handleReceivedMediaWithEnvelope:incomingEnvelope dataMessage:dataMessage];
    } else {
        [self handleReceivedTextMessageWithEnvelope:incomingEnvelope dataMessage:dataMessage];
        if ([self isDataMessageGroupAvatarUpdate:dataMessage]) {
            DDLogVerbose(@"%@ Data message had group avatar attachment", self.tag);
            [self handleReceivedGroupAvatarUpdateWithEnvelope:incomingEnvelope dataMessage:dataMessage];
        }
    }
}

- (void)handleIncomingEnvelope:(OWSSignalServiceProtosEnvelope *)incomingEnvelope
               withCallMessage:(OWSSignalServiceProtosCallMessage *)callMessage
{
    if (callMessage.hasOffer) {
        [self.callMessageHandler receivedOffer:callMessage.offer fromCallerId:incomingEnvelope.source];
    } else if (callMessage.hasAnswer) {
        [self.callMessageHandler receivedAnswer:callMessage.answer fromCallerId:incomingEnvelope.source];
    } else if (callMessage.iceUpdate.count > 0) {
        for (OWSSignalServiceProtosCallMessageIceUpdate *iceUpdate in callMessage.iceUpdate) {
            [self.callMessageHandler receivedIceUpdate:iceUpdate fromCallerId:incomingEnvelope.source];
        }
    } else if (callMessage.hasHangup) {
        DDLogVerbose(@"%@ Received CallMessage with Hangup.", self.tag);
        [self.callMessageHandler receivedHangup:callMessage.hangup fromCallerId:incomingEnvelope.source];
    } else if (callMessage.hasBusy) {
        [self.callMessageHandler receivedBusy:callMessage.busy fromCallerId:incomingEnvelope.source];
    } else {
        DDLogWarn(@"%@ Ignoring Received CallMessage without actionable content: %@", self.tag, callMessage);
    }
}

- (void)handleReceivedGroupAvatarUpdateWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                                        dataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
{
    OWSAssert([NSThread isMainThread]);
    TSGroupThread *groupThread = [TSGroupThread getOrCreateThreadWithGroupIdData:dataMessage.group.id];
    OWSAttachmentsProcessor *attachmentsProcessor =
        [[OWSAttachmentsProcessor alloc] initWithAttachmentProtos:@[ dataMessage.group.avatar ]
                                                        timestamp:envelope.timestamp
                                                            relay:envelope.relay
                                                           thread:groupThread
                                                   networkManager:self.networkManager];

    if (!attachmentsProcessor.hasSupportedAttachments) {
        DDLogWarn(@"%@ received unsupported group avatar envelope", self.tag);
        return;
    }
    [attachmentsProcessor fetchAttachmentsForMessage:nil
        success:^(TSAttachmentStream *attachmentStream) {
            [groupThread updateAvatarWithAttachmentStream:attachmentStream];
        }
        failure:^(NSError *error) {
            DDLogError(@"%@ failed to fetch attachments for group avatar sent at: %llu. with error: %@",
                self.tag,
                envelope.timestamp,
                error);
        }];
}

- (void)handleReceivedMediaWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                            dataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
{
    OWSAssert([NSThread isMainThread]);
    TSThread *thread = [self threadForEnvelope:envelope dataMessage:dataMessage];
    OWSAttachmentsProcessor *attachmentsProcessor =
        [[OWSAttachmentsProcessor alloc] initWithAttachmentProtos:dataMessage.attachments
                                                        timestamp:envelope.timestamp
                                                            relay:envelope.relay
                                                           thread:thread
                                                   networkManager:self.networkManager];
    if (!attachmentsProcessor.hasSupportedAttachments) {
        DDLogWarn(@"%@ received unsupported media envelope", self.tag);
        return;
    }

    TSIncomingMessage *_Nullable createdMessage =
        [self handleReceivedEnvelope:envelope
                     withDataMessage:dataMessage
                       attachmentIds:attachmentsProcessor.supportedAttachmentIds];

    if (!createdMessage) {
        return;
    }

    DDLogDebug(@"%@ incoming attachment message: %@", self.tag, createdMessage.debugDescription);

    [attachmentsProcessor fetchAttachmentsForMessage:createdMessage
        success:^(TSAttachmentStream *attachmentStream) {
            DDLogDebug(
                @"%@ successfully fetched attachment: %@ for message: %@", self.tag, attachmentStream, createdMessage);
        }
        failure:^(NSError *error) {
            DDLogError(
                @"%@ failed to fetch attachments for message: %@ with error: %@", self.tag, createdMessage, error);
        }];
}

- (void)handleIncomingEnvelope:(OWSSignalServiceProtosEnvelope *)messageEnvelope
               withSyncMessage:(OWSSignalServiceProtosSyncMessage *)syncMessage
{
    OWSAssert([NSThread isMainThread]);
    if (syncMessage.hasSent) {
        OWSIncomingSentMessageTranscript *transcript =
            [[OWSIncomingSentMessageTranscript alloc] initWithProto:syncMessage.sent relay:messageEnvelope.relay];

        OWSRecordTranscriptJob *recordJob =
            [[OWSRecordTranscriptJob alloc] initWithIncomingSentMessageTranscript:transcript
                                                                    messageSender:self.messageSender
                                                                   networkManager:self.networkManager];

        if ([self isDataMessageGroupAvatarUpdate:syncMessage.sent.message]) {
            [recordJob runWithAttachmentHandler:^(TSAttachmentStream *attachmentStream) {
                TSGroupThread *groupThread =
                    [TSGroupThread getOrCreateThreadWithGroupIdData:syncMessage.sent.message.group.id];
                [groupThread updateAvatarWithAttachmentStream:attachmentStream];
            }];
        } else {
            [recordJob runWithAttachmentHandler:^(TSAttachmentStream *attachmentStream) {
                DDLogDebug(@"%@ successfully fetched transcript attachment: %@", self.tag, attachmentStream);
            }];
        }
    } else if (syncMessage.hasRequest) {
        if (syncMessage.request.type == OWSSignalServiceProtosSyncMessageRequestTypeContacts) {
            OWSSyncContactsMessage *syncContactsMessage =
            [[OWSSyncContactsMessage alloc] initWithContactsManager:self.contactsManager
                                                    identityManager:self.identityManager];
            
            [self.messageSender sendTemporaryAttachmentData:[syncContactsMessage buildPlainTextAttachmentData]
                                                contentType:OWSMimeTypeApplicationOctetStream
                                                  inMessage:syncContactsMessage
                                                    success:^{
                                                        DDLogInfo(@"%@ Successfully sent Contacts response syncMessage.", self.tag);
                                                    }
                                                    failure:^(NSError *error) {
                                                        DDLogError(@"%@ Failed to send Contacts response syncMessage with error: %@", self.tag, error);
                                                    }];
        } else if (syncMessage.request.type == OWSSignalServiceProtosSyncMessageRequestTypeGroups) {
            OWSSyncGroupsMessage *syncGroupsMessage = [[OWSSyncGroupsMessage alloc] init];
            
            [self.messageSender sendTemporaryAttachmentData:[syncGroupsMessage buildPlainTextAttachmentData]
                                                contentType:OWSMimeTypeApplicationOctetStream
                                                  inMessage:syncGroupsMessage
                                                    success:^{
                                                        DDLogInfo(@"%@ Successfully sent Groups response syncMessage.", self.tag);
                                                    }
                                                    failure:^(NSError *error) {
                                                        DDLogError(@"%@ Failed to send Groups response syncMessage with error: %@", self.tag, error);
                                                    }];
        } else {
            DDLogWarn(@"%@ ignoring unsupported sync request message", self.tag);
        }
    } else if (syncMessage.hasBlocked) {
        NSArray<NSString *> *blockedPhoneNumbers = [syncMessage.blocked.numbers copy];
        [_blockingManager setBlockedPhoneNumbers:blockedPhoneNumbers sendSyncMessage:NO];
    } else if (syncMessage.read.count > 0) {
        DDLogInfo(@"%@ Received %ld read receipt(s)", self.tag, (u_long)syncMessage.read.count);

        OWSReadReceiptsProcessor *readReceiptsProcessor =
            [[OWSReadReceiptsProcessor alloc] initWithReadReceiptProtos:syncMessage.read
                                                         storageManager:self.storageManager];
        [readReceiptsProcessor process];
    } else if (syncMessage.hasVerified) {
        DDLogInfo(@"%@ Received verification state for %@", self.tag, syncMessage.verified.destination);
        [self.identityManager processIncomingSyncMessage:syncMessage.verified];
    } else {
        DDLogWarn(@"%@ Ignoring unsupported sync message.", self.tag);
    }
}

- (void)handleEndSessionMessageWithEnvelope:(OWSSignalServiceProtosEnvelope *)endSessionEnvelope
                                dataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
{
    OWSAssert([NSThread isMainThread]);
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSContactThread *thread =
            [TSContactThread getOrCreateThreadWithContactId:endSessionEnvelope.source transaction:transaction];
        uint64_t timeStamp = endSessionEnvelope.timestamp;

        if (thread) { // TODO thread should always be nonnull.
            [[[TSInfoMessage alloc] initWithTimestamp:timeStamp
                                             inThread:thread
                                          messageType:TSInfoMessageTypeSessionDidEnd] saveWithTransaction:transaction];
        }
    }];

    dispatch_async([OWSDispatch sessionStoreQueue], ^{
        [[TSStorageManager sharedManager] deleteAllSessionsForContact:endSessionEnvelope.source];
    });
}

- (void)handleExpirationTimerUpdateMessageWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                                           dataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
{
    OWSAssert([NSThread isMainThread]);
    TSThread *thread = [self threadForEnvelope:envelope dataMessage:dataMessage];

    OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration;
    if (dataMessage.hasExpireTimer && dataMessage.expireTimer > 0) {
        DDLogInfo(@"%@ Expiring messages duration turned to %u for thread %@",
            self.tag,
            (unsigned int)dataMessage.expireTimer,
            thread);
        disappearingMessagesConfiguration =
            [[OWSDisappearingMessagesConfiguration alloc] initWithThreadId:thread.uniqueId
                                                                   enabled:YES
                                                           durationSeconds:dataMessage.expireTimer];
    } else {
        DDLogInfo(@"%@ Expiring messages have been turned off for thread %@", self.tag, thread);
        disappearingMessagesConfiguration = [[OWSDisappearingMessagesConfiguration alloc]
            initWithThreadId:thread.uniqueId
                     enabled:NO
             durationSeconds:OWSDisappearingMessagesConfigurationDefaultExpirationDuration];
    }
    [disappearingMessagesConfiguration save];
    NSString *name = [self.contactsManager displayNameForPhoneIdentifier:envelope.source];
    OWSDisappearingConfigurationUpdateInfoMessage *message =
        [[OWSDisappearingConfigurationUpdateInfoMessage alloc] initWithTimestamp:envelope.timestamp
                                                                          thread:thread
                                                                   configuration:disappearingMessagesConfiguration
                                                             createdByRemoteName:name];
    [message save];
}

- (void)handleReceivedTextMessageWithEnvelope:(OWSSignalServiceProtosEnvelope *)textMessageEnvelope
                                  dataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
{
    OWSAssert([NSThread isMainThread]);
    [self handleReceivedEnvelope:textMessageEnvelope withDataMessage:dataMessage attachmentIds:@[]];
}

- (void)sendGroupUpdateForThread:(TSGroupThread *)gThread message:(TSOutgoingMessage *)message
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(gThread);
    OWSAssert(message);

    if (gThread.groupModel.groupImage) {
        [self.messageSender sendAttachmentData:UIImagePNGRepresentation(gThread.groupModel.groupImage)
            contentType:OWSMimeTypeImagePng
            sourceFilename:nil
            inMessage:message
            success:^{
                DDLogDebug(@"%@ Successfully sent group update with avatar", self.tag);
            }
            failure:^(NSError *error) {
                DDLogError(@"%@ Failed to send group avatar update with error: %@", self.tag, error);
            }];
    } else {
        [self.messageSender sendMessage:message
            success:^{
                DDLogDebug(@"%@ Successfully sent group update", self.tag);
            }
            failure:^(NSError *error) {
                DDLogError(@"%@ Failed to send group update with error: %@", self.tag, error);
            }];
    }
}

- (void)handleGroupInfoRequest:(OWSSignalServiceProtosEnvelope *)envelope
                   dataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(dataMessage.group.type == OWSSignalServiceProtosGroupContextTypeRequestInfo);

    NSData *groupId = dataMessage.hasGroup ? dataMessage.group.id : nil;
    if (!groupId) {
        OWSFail(@"Group info request is missing group id.");
        return;
    }

    DDLogWarn(@"%@ Received 'Request Group Info' message for group: %@ from: %@", self.tag, groupId, envelope.source);

    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSGroupModel *emptyModelToFillOutId =
            [[TSGroupModel alloc] initWithTitle:nil memberIds:nil image:nil groupId:dataMessage.group.id];
        TSGroupThread *gThread = [TSGroupThread threadWithGroupModel:emptyModelToFillOutId transaction:transaction];
        if (!gThread) {
            DDLogWarn(@"%@ Unknown group: %@", self.tag, groupId);
            return;
        }

        if (![gThread.groupModel.groupMemberIds containsObject:envelope.source]) {
            DDLogWarn(@"%@ Ignoring 'Request Group Info' message for non-member of group. %@ not in %@",
                self.tag,
                envelope.source,
                gThread.groupModel.groupMemberIds);
        }

        NSString *updateGroupInfo =
            [gThread.groupModel getInfoStringAboutUpdateTo:gThread.groupModel contactsManager:self.contactsManager];
        TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                         inThread:gThread
                                                                 groupMetaMessage:TSGroupMessageUpdate];
        [message updateWithCustomMessage:updateGroupInfo transaction:transaction];
        // Only send this group update to the requester.
        [message updateWithSingleGroupRecipient:envelope.source transaction:transaction];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self sendGroupUpdateForThread:gThread message:message];
        });
    }];
}

- (TSIncomingMessage *_Nullable)handleReceivedEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                                       withDataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
                                         attachmentIds:(NSArray<NSString *> *)attachmentIds
{
    OWSAssert([NSThread isMainThread]);
    uint64_t timestamp = envelope.timestamp;
    NSString *body = dataMessage.body;
    NSData *groupId = dataMessage.hasGroup ? dataMessage.group.id : nil;

    __block TSIncomingMessage *_Nullable incomingMessage;
    __block TSThread *thread;

    // Do this outside of a transaction to avoid deadlock
    OWSAssert([TSAccountManager isRegistered]);
    NSString *localNumber = [TSAccountManager localNumber];

    if (dataMessage.group.type == OWSSignalServiceProtosGroupContextTypeRequestInfo) {
        [self handleGroupInfoRequest:envelope dataMessage:dataMessage];
        return nil;
    }

    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      if (groupId) {
          NSMutableArray *uniqueMemberIds = [[[NSSet setWithArray:dataMessage.group.members] allObjects] mutableCopy];
          TSGroupModel *model = [[TSGroupModel alloc] initWithTitle:dataMessage.group.name
                                                          memberIds:uniqueMemberIds
                                                              image:nil
                                                            groupId:dataMessage.group.id];
          TSGroupThread *gThread = [TSGroupThread getOrCreateThreadWithGroupModel:model transaction:transaction];
          [gThread saveWithTransaction:transaction];

          switch (dataMessage.group.type) {
              case OWSSignalServiceProtosGroupContextTypeUpdate: {
                  NSString *updateGroupInfo =
                      [gThread.groupModel getInfoStringAboutUpdateTo:model contactsManager:self.contactsManager];
                  gThread.groupModel = model;
                  [gThread saveWithTransaction:transaction];
                  [[[TSInfoMessage alloc] initWithTimestamp:timestamp
                                                   inThread:gThread
                                                messageType:TSInfoMessageTypeGroupUpdate
                                              customMessage:updateGroupInfo] saveWithTransaction:transaction];
                  break;
              }
              case OWSSignalServiceProtosGroupContextTypeQuit: {
                  NSString *nameString = [self.contactsManager displayNameForPhoneIdentifier:envelope.source];

                  NSString *updateGroupInfo =
                      [NSString stringWithFormat:NSLocalizedString(@"GROUP_MEMBER_LEFT", @""), nameString];
                  NSMutableArray *newGroupMembers = [NSMutableArray arrayWithArray:gThread.groupModel.groupMemberIds];
                  [newGroupMembers removeObject:envelope.source];
                  gThread.groupModel.groupMemberIds = newGroupMembers;

                  [gThread saveWithTransaction:transaction];
                  [[[TSInfoMessage alloc] initWithTimestamp:timestamp
                                                   inThread:gThread
                                                messageType:TSInfoMessageTypeGroupUpdate
                                              customMessage:updateGroupInfo] saveWithTransaction:transaction];
                  break;
              }
              case OWSSignalServiceProtosGroupContextTypeDeliver: {
                  incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:timestamp
                                                                        inThread:gThread
                                                                        authorId:envelope.source
                                                                  sourceDeviceId:envelope.sourceDevice
                                                                     messageBody:body
                                                                   attachmentIds:attachmentIds
                                                                expiresInSeconds:dataMessage.expireTimer];
                  DDLogDebug(@"%@ incoming group text message: %@", self.tag, incomingMessage.debugDescription);
                  [incomingMessage saveWithTransaction:transaction];
                  break;
              }
              default: {
                  DDLogWarn(@"%@ Ignoring unknown group message type:%d", self.tag, (int)dataMessage.group.type);
              }
          }

          thread = gThread;
      } else {
          TSContactThread *cThread = [TSContactThread getOrCreateThreadWithContactId:envelope.source
                                                                         transaction:transaction
                                                                               relay:envelope.relay];

          incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:timestamp
                                                                inThread:cThread
                                                                authorId:[cThread contactIdentifier]
                                                          sourceDeviceId:envelope.sourceDevice
                                                             messageBody:body
                                                           attachmentIds:attachmentIds
                                                        expiresInSeconds:dataMessage.expireTimer];
          DDLogDebug(@"%@ incoming 1:1 text message: %@", self.tag, incomingMessage.debugDescription);
          [incomingMessage saveWithTransaction:transaction];
          thread = cThread;
      }

      if (thread && incomingMessage) {
          // Any messages sent from the current user - from this device or another - should be
          // automatically marked as read.
          BOOL shouldMarkMessageAsRead = [envelope.source isEqualToString:localNumber];
          if (shouldMarkMessageAsRead) {
              // Don't send a read receipt for messages sent by ourselves.
              [incomingMessage markAsReadWithTransaction:transaction sendReadReceipt:NO updateExpiration:YES];
          }

          DDLogDebug(@"%@ shouldMarkMessageAsRead: %d (%@)", self.tag, shouldMarkMessageAsRead, envelope.source);

          // Other clients allow attachments to be sent along with body, we want the text displayed as a separate
          // message
          if ([attachmentIds count] > 0 && body != nil && ![body isEqualToString:@""]) {
              // We want the text to be displayed under the attachment
              uint64_t textMessageTimestamp = timestamp + 1;
              TSIncomingMessage *textMessage = [[TSIncomingMessage alloc] initWithTimestamp:textMessageTimestamp
                                                                                   inThread:thread
                                                                                   authorId:envelope.source
                                                                             sourceDeviceId:envelope.sourceDevice
                                                                                messageBody:body
                                                                              attachmentIds:@[]
                                                                           expiresInSeconds:dataMessage.expireTimer];
              DDLogDebug(@"%@ incoming extra text message: %@", self.tag, incomingMessage.debugDescription);
              [textMessage saveWithTransaction:transaction];
          }
      }
    }];

    if (incomingMessage && thread) {
        // In case we already have a read receipt for this new message (happens sometimes).
        OWSReadReceiptsProcessor *readReceiptsProcessor =
            [[OWSReadReceiptsProcessor alloc] initWithIncomingMessage:incomingMessage
                                                       storageManager:self.storageManager];
        [readReceiptsProcessor process];

        [OWSDisappearingMessagesJob becomeConsistentWithConfigurationForMessage:incomingMessage
                                                                contactsManager:self.contactsManager];

        // Update thread preview in inbox
        [thread touch];

        [[TextSecureKitEnv sharedEnv].notificationsManager notifyUserForIncomingMessage:incomingMessage
                                                                               inThread:thread
                                                                        contactsManager:self.contactsManager];
    }

    return incomingMessage;
}

- (void)processException:(NSException *)exception envelope:(OWSSignalServiceProtosEnvelope *)envelope
{
    OWSAssert([NSThread isMainThread]);
    DDLogError(@"%@ Got exception: %@ of type: %@ with reason: %@",
        self.tag,
        exception.description,
        exception.name,
        exception.reason);

    __block TSErrorMessage *errorMessage;
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      if ([exception.name isEqualToString:NoSessionException]) {
          OWSProdErrorWEnvelope(@"message_manager_error_no_session", envelope);
          errorMessage = [TSErrorMessage missingSessionWithEnvelope:envelope withTransaction:transaction];
      } else if ([exception.name isEqualToString:InvalidKeyException]) {
          OWSProdErrorWEnvelope(@"message_manager_error_invalid_key", envelope);
          errorMessage = [TSErrorMessage invalidKeyExceptionWithEnvelope:envelope withTransaction:transaction];
      } else if ([exception.name isEqualToString:InvalidKeyIdException]) {
          OWSProdErrorWEnvelope(@"message_manager_error_invalid_key_id", envelope);
          errorMessage = [TSErrorMessage invalidKeyExceptionWithEnvelope:envelope withTransaction:transaction];
      } else if ([exception.name isEqualToString:DuplicateMessageException]) {
          // Duplicate messages are dismissed
          return;
      } else if ([exception.name isEqualToString:InvalidVersionException]) {
          OWSProdErrorWEnvelope(@"message_manager_error_invalid_message_version", envelope);
          errorMessage = [TSErrorMessage invalidVersionWithEnvelope:envelope withTransaction:transaction];
      } else if ([exception.name isEqualToString:UntrustedIdentityKeyException]) {
          // Should no longer get here, since we now record the new identity for incoming messages.
          OWSProdErrorWEnvelope(@"message_manager_error_untrusted_identity_key_exception", envelope);
          OWSFail(@"%@ Failed to trust identity on incoming message from: %@.%d",
              self.tag,
              envelope.source,
              envelope.sourceDevice);
          return;
      } else {
          OWSProdErrorWEnvelope(@"message_manager_error_corrupt_message", envelope);
          errorMessage = [TSErrorMessage corruptedMessageWithEnvelope:envelope withTransaction:transaction];
      }

      [errorMessage saveWithTransaction:transaction];
    }];

    if (errorMessage != nil) {
        [self notififyForErrorMessage:errorMessage withEnvelope:envelope];
    }
}

- (void)notififyForErrorMessage:(TSErrorMessage *)errorMessage withEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
{
    TSThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:envelope.source];
    [[TextSecureKitEnv sharedEnv].notificationsManager notifyUserForErrorMessage:errorMessage inThread:contactThread];
}

#pragma mark - helpers

- (BOOL)isDataMessageGroupAvatarUpdate:(OWSSignalServiceProtosDataMessage *)dataMessage
{
    return dataMessage.hasGroup
        && dataMessage.group.type == OWSSignalServiceProtosGroupContextTypeUpdate
        && dataMessage.group.hasAvatar;
}

/**
 * @returns
 *   Group or Contact thread for message, creating a new one if necessary.
 */
- (TSThread *)threadForEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                    dataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
{
    if (dataMessage.hasGroup) {
        return [TSGroupThread getOrCreateThreadWithGroupIdData:dataMessage.group.id];
    } else {
        return [TSContactThread getOrCreateThreadWithContactId:envelope.source];
    }
}

- (NSUInteger)unreadMessagesCount {
    __block NSUInteger numberOfItems;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      numberOfItems = [[transaction ext:TSUnreadDatabaseViewExtensionName] numberOfItemsInAllGroups];
    }];

    return numberOfItems;
}

- (NSUInteger)unreadMessagesCountExcept:(TSThread *)thread {
    __block NSUInteger numberOfItems;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      numberOfItems = [[transaction ext:TSUnreadDatabaseViewExtensionName] numberOfItemsInAllGroups];
      numberOfItems =
          numberOfItems - [[transaction ext:TSUnreadDatabaseViewExtensionName] numberOfItemsInGroup:thread.uniqueId];
    }];

    return numberOfItems;
}

- (void)updateApplicationBadgeCount
{
    NSUInteger numberOfItems = [self unreadMessagesCount];
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:numberOfItems];
}

- (NSUInteger)unreadMessagesInThread:(TSThread *)thread {
    __block NSUInteger numberOfItems;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      numberOfItems = [[transaction ext:TSUnreadDatabaseViewExtensionName] numberOfItemsInGroup:thread.uniqueId];
    }];
    return numberOfItems;
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
