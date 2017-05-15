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

@interface TSMessagesManager ()

@property (nonatomic, readonly) id<OWSCallMessageHandler> callMessageHandler;
@property (nonatomic, readonly) id<ContactsManagerProtocol> contactsManager;
@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) OWSIncomingMessageFinder *incomingMessageFinder;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;

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
    OWSMessageSender *messageSender = [TextSecureKitEnv sharedEnv].messageSender;

    return [self initWithNetworkManager:networkManager
                         storageManager:storageManager
                     callMessageHandler:callMessageHandler
                        contactsManager:contactsManager
                        contactsUpdater:contactsUpdater
                          messageSender:messageSender];
}

- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager
                        storageManager:(TSStorageManager *)storageManager
                    callMessageHandler:(id<OWSCallMessageHandler>)callMessageHandler
                       contactsManager:(id<ContactsManagerProtocol>)contactsManager
                       contactsUpdater:(ContactsUpdater *)contactsUpdater
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
    _messageSender = messageSender;

    _dbConnection = storageManager.newDatabaseConnection;
    _incomingMessageFinder = [[OWSIncomingMessageFinder alloc] initWithDatabase:storageManager.database];
    _blockingManager = [OWSBlockingManager sharedManager];

    OWSSingletonAssert();

    return self;
}

#pragma mark - Debugging

- (NSString *)descriptionForEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
{
    OWSAssert(envelope != nil);
    NSString *envelopeType;
    switch (envelope.type) {
        case OWSSignalServiceProtosEnvelopeTypeReceipt:
            envelopeType = @"DeliveryReceipt";
            break;
        case OWSSignalServiceProtosEnvelopeTypeUnknown:
            // Shouldn't happen
            OWSAssert(NO);
            envelopeType = @"Unknown";
            break;
        case OWSSignalServiceProtosEnvelopeTypeCiphertext:
            envelopeType = @"SignalEncryptedMessage";
            break;
        case OWSSignalServiceProtosEnvelopeTypeKeyExchange:
            // Unsupported
            OWSAssert(NO);
            envelopeType = @"KeyExchange";
            break;
        case OWSSignalServiceProtosEnvelopeTypePrekeyBundle:
            envelopeType = @"PreKeyEncryptedMessage";
            break;
        default:
            // Shouldn't happen
            OWSAssert(NO);
            envelopeType = @"Other";
            break;
    }

    return [NSString stringWithFormat:@"<Envelope type: %@, source: %@.%d, timestamp: %llu content.length: %lu />",
                     envelopeType,
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
    } else {
        OWSAssert(NO);
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
    NSMutableString *description = [[NSMutableString alloc] initWithString:@"CallMessage: "];
    if (syncMessage.hasSent) {
        [description appendString:@"SentTranscript"];
    } else if (syncMessage.hasRequest) {
        if (syncMessage.request.type == OWSSignalServiceProtosSyncMessageRequestTypeContacts) {
            [description appendString:@"ContactRequest"];
        } else if (syncMessage.request.type == OWSSignalServiceProtosSyncMessageRequestTypeGroups) {
            [description appendString:@"GroupRequest"];
        } else {
            // Shouldn't happen
            OWSAssert(NO);
            [description appendString:@"UnknownRequest"];
        }
    } else if (syncMessage.hasBlocked) {
        [description appendString:@"Blocked"];
    } else if (syncMessage.read.count > 0) {
        [description appendString:@"ReadReceipt"];
    } else {
        // Shouldn't happen
        OWSAssert(NO);
        [description appendString:@"Unknown"];
    }

    return description;
}

#pragma mark - message handling

- (void)handleReceivedEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
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
                                                @"%@ handling secure message failed with error: %@", self.tag, error);
                                        }
                                        completion();
                                    }];
                // Return to avoid double-acknowledging.
                return;
            }
            case OWSSignalServiceProtosEnvelopeTypePrekeyBundle: {
                [self handlePreKeyBundleAsync:envelope
                                   completion:^(NSError *_Nullable error) {
                                       DDLogDebug(@"%@ handled pre-key bundle", self.tag);
                                       if (error) {
                                           DDLogError(
                                               @"%@ handling pre-key bundle failed with error: %@", self.tag, error);
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
            if (![storageManager containsSession:recipientId deviceId:deviceId]) {
                [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    TSErrorMessage *errorMessage =
                        [TSErrorMessage missingSessionWithEnvelope:messageEnvelope withTransaction:transaction];
                    [errorMessage saveWithTransaction:transaction];
                }];
                DDLogError(@"Skipping message envelope for unknown session.");
                completion(nil);
                return;
            }

            // DEPRECATED - Remove after all clients have been upgraded.
            NSData *encryptedData
                = messageEnvelope.hasContent ? messageEnvelope.content : messageEnvelope.legacyMessage;
            if (!encryptedData) {
                DDLogError(@"Skipping message envelope which had no encrypted data.");
                completion(nil);
                return;
            }

            NSUInteger kMaxEncryptedDataLength = 250 * 1024;
            if (encryptedData.length > kMaxEncryptedDataLength) {
                DDLogError(@"Skipping message envelope with oversize encrypted data: %lu.",
                    (unsigned long)encryptedData.length);
                completion(nil);
                return;
            }

            NSData *plaintextData;

            @try {
                WhisperMessage *message = [[WhisperMessage alloc] initWithData:encryptedData];
                SessionCipher *cipher = [[SessionCipher alloc] initWithSessionStore:storageManager
                                                                        preKeyStore:storageManager
                                                                  signedPreKeyStore:storageManager
                                                                   identityKeyStore:storageManager
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
            DDLogError(@"Skipping message envelope which had no encrypted data");
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
                                                                   identityKeyStore:storageManager
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
        DDLogInfo(@"%@ Ignoring previously received envelope with timestamp: %llu", self.tag, envelope.timestamp);
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
            [[TSStorageManager sharedManager].dbConnection
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
            [[OWSSyncContactsMessage alloc] initWithContactsManager:self.contactsManager];
            
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
        OWSAssert(groupId);
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
          thread = cThread;
      }

      if (thread && incomingMessage) {
          [incomingMessage saveWithTransaction:transaction];

          // Any messages sent from the current user - from this device or another - should be
          // automatically marked as read.
          BOOL shouldMarkMessageAsRead = [envelope.source isEqualToString:localNumber];
          if (shouldMarkMessageAsRead) {
              [incomingMessage markAsReadLocallyWithTransaction:transaction];
          }

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

        // TODO Delay notification by 100ms?
        // It's pretty annoying when you're phone keeps buzzing while you're having a conversation on Desktop.
        NSString *name = [thread name];
        [[TextSecureKitEnv sharedEnv].notificationsManager notifyUserForIncomingMessage:incomingMessage
                                                                                   from:name
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
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      TSErrorMessage *errorMessage;

      if ([exception.name isEqualToString:NoSessionException]) {
          errorMessage = [TSErrorMessage missingSessionWithEnvelope:envelope withTransaction:transaction];
      } else if ([exception.name isEqualToString:InvalidKeyException]) {
          errorMessage = [TSErrorMessage invalidKeyExceptionWithEnvelope:envelope withTransaction:transaction];
      } else if ([exception.name isEqualToString:InvalidKeyIdException]) {
          errorMessage = [TSErrorMessage invalidKeyExceptionWithEnvelope:envelope withTransaction:transaction];
      } else if ([exception.name isEqualToString:DuplicateMessageException]) {
          // Duplicate messages are dismissed
          return;
      } else if ([exception.name isEqualToString:InvalidVersionException]) {
          errorMessage = [TSErrorMessage invalidVersionWithEnvelope:envelope withTransaction:transaction];
      } else if ([exception.name isEqualToString:UntrustedIdentityKeyException]) {
          errorMessage =
              [TSInvalidIdentityKeyReceivingErrorMessage untrustedKeyWithEnvelope:envelope withTransaction:transaction];
      } else {
          errorMessage = [TSErrorMessage corruptedMessageWithEnvelope:envelope withTransaction:transaction];
      }

      [errorMessage saveWithTransaction:transaction];
    }];
}

#pragma mark - helpers

- (BOOL)isDataMessageGroupAvatarUpdate:(OWSSignalServiceProtosDataMessage *)dataMessage
{
    return dataMessage.hasGroup
        && dataMessage.group.type == OWSSignalServiceProtosGroupContextTypeUpdate
        && dataMessage.group.hasAvatar;
}

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
