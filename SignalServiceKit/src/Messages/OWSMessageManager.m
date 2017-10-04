//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageManager.h"
#import "ContactsManagerProtocol.h"
#import "Cryptography.h"
#import "MimeTypeUtil.h"
#import "NSDate+OWS.h"
#import "NotificationsProtocol.h"
#import "OWSAttachmentsProcessor.h"
#import "OWSBlockingManager.h"
#import "OWSCallMessageHandler.h"
#import "OWSDisappearingConfigurationUpdateInfoMessage.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSIdentityManager.h"
#import "OWSIncomingMessageFinder.h"
#import "OWSIncomingSentMessageTranscript.h"
#import "OWSMessageSender.h"
#import "OWSReadReceiptManager.h"
#import "OWSRecordTranscriptJob.h"
#import "OWSSyncConfigurationMessage.h"
#import "OWSSyncContactsMessage.h"
#import "OWSSyncGroupsMessage.h"
#import "OWSSyncGroupsRequestMessage.h"
#import "ProfileManagerProtocol.h"
#import "TSAccountManager.h"
#import "TSContactThread.h"
#import "TSDatabaseView.h"
#import "TSGroupModel.h"
#import "TSGroupThread.h"
#import "TSIncomingMessage.h"
#import "TSInfoMessage.h"
#import "TSNetworkManager.h"
#import "TSOutgoingMessage.h"
#import "TSStorageManager+SessionStore.h"
#import "TSStorageManager.h"
#import "TextSecureKitEnv.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageManager ()

@property (nonatomic, readonly) id<OWSCallMessageHandler> callMessageHandler;
@property (nonatomic, readonly) id<ContactsManagerProtocol> contactsManager;
@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) OWSIncomingMessageFinder *incomingMessageFinder;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
@property (nonatomic, readonly) OWSIdentityManager *identityManager;
@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@end

#pragma mark -

@implementation OWSMessageManager

+ (instancetype)sharedManager
{
    static OWSMessageManager *sharedMyManager = nil;
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
    OWSIdentityManager *identityManager = [OWSIdentityManager sharedManager];
    OWSMessageSender *messageSender = [TextSecureKitEnv sharedEnv].messageSender;


    return [self initWithNetworkManager:networkManager
                         storageManager:storageManager
                     callMessageHandler:callMessageHandler
                        contactsManager:contactsManager
                        identityManager:identityManager
                          messageSender:messageSender];
}

- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager
                        storageManager:(TSStorageManager *)storageManager
                    callMessageHandler:(id<OWSCallMessageHandler>)callMessageHandler
                       contactsManager:(id<ContactsManagerProtocol>)contactsManager
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

#pragma mark - Blocking

- (BOOL)isEnvelopeBlocked:(OWSSignalServiceProtosEnvelope *)envelope
{
    OWSAssert(envelope);

    return [_blockingManager isRecipientIdBlocked:envelope.source];
}

#pragma mark - message handling

- (void)processEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
          plaintextData:(NSData *_Nullable)plaintextData
            transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(envelope);
    OWSAssert(transaction);
    OWSAssert([TSAccountManager isRegistered]);

    DDLogInfo(@"%@ handling decrypted envelope: %@", self.tag, [self descriptionForEnvelope:envelope]);

    OWSAssert(envelope.source.length > 0);
    OWSAssert(![self isEnvelopeBlocked:envelope]);

    switch (envelope.type) {
        case OWSSignalServiceProtosEnvelopeTypeCiphertext:
        case OWSSignalServiceProtosEnvelopeTypePrekeyBundle:
            if (plaintextData) {
                [self handleEnvelope:envelope plaintextData:plaintextData transaction:transaction];
            } else {
                OWSFail(
                    @"%@ missing decrypted data for envelope: %@", self.tag, [self descriptionForEnvelope:envelope]);
            }
            break;
        case OWSSignalServiceProtosEnvelopeTypeReceipt:
            OWSAssert(!plaintextData);
            [self handleDeliveryReceipt:envelope transaction:transaction];
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
}

- (void)handleDeliveryReceipt:(OWSSignalServiceProtosEnvelope *)envelope
                  transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(envelope);
    OWSAssert(transaction);

    // Old-style delivery notices don't include a "delivery timestamp".
    [self processDeliveryReceiptsFromRecipientId:envelope.source
                                  sentTimestamps:@[
                                      @(envelope.timestamp),
                                  ]
                               deliveryTimestamp:nil
                                     transaction:transaction];
}

// deliveryTimestamp is an optional parameter, since legacy
// delivery receipts don't have a "delivery timestamp".  Those
// messages repurpose the "timestamp" field to indicate when the
// corresponding message was originally sent.
- (void)processDeliveryReceiptsFromRecipientId:(NSString *)recipientId
                                sentTimestamps:(NSArray<NSNumber *> *)sentTimestamps
                             deliveryTimestamp:(NSNumber *_Nullable)deliveryTimestamp
                                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(recipientId);
    OWSAssert(sentTimestamps);
    OWSAssert(transaction);

    for (NSNumber *nsTimestamp in sentTimestamps) {
        uint64_t timestamp = [nsTimestamp unsignedLongLongValue];

        NSArray<TSOutgoingMessage *> *messages
            = (NSArray<TSOutgoingMessage *> *)[TSInteraction interactionsWithTimestamp:timestamp
                                                                               ofClass:[TSOutgoingMessage class]
                                                                       withTransaction:transaction];
        if (messages.count < 1) {
            // The service sends delivery receipts for "unpersisted" messages
            // like group updates, so these errors are expected to a certain extent.
            //
            // TODO: persist "early" delivery receipts.
            DDLogInfo(@"%@ Missing message for delivery receipt: %llu", self.tag, timestamp);
        } else {
            if (messages.count > 1) {
                DDLogInfo(
                    @"%@ More than one message (%zd) for delivery receipt: %llu", self.tag, messages.count, timestamp);
            }
            for (TSOutgoingMessage *outgoingMessage in messages) {
                [outgoingMessage updateWithDeliveredToRecipientId:recipientId
                                                deliveryTimestamp:deliveryTimestamp
                                                      transaction:transaction];
            }
        }
    }
}

- (void)handleEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
         plaintextData:(NSData *)plaintextData
           transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(envelope);
    OWSAssert(plaintextData);
    OWSAssert(transaction);
    OWSAssert(envelope.hasTimestamp && envelope.timestamp > 0);
    OWSAssert(envelope.hasSource && envelope.source.length > 0);
    OWSAssert(envelope.hasSourceDevice && envelope.sourceDevice > 0);

    BOOL duplicateEnvelope = [self.incomingMessageFinder existsMessageWithTimestamp:envelope.timestamp
                                                                           sourceId:envelope.source
                                                                     sourceDeviceId:envelope.sourceDevice
                                                                        transaction:transaction];
    if (duplicateEnvelope) {
        DDLogInfo(@"%@ Ignoring previously received envelope from %@ with timestamp: %llu",
            self.tag,
            envelopeAddress(envelope),
            envelope.timestamp);
        return;
    }

    if (envelope.hasContent) {
        OWSSignalServiceProtosContent *content = [OWSSignalServiceProtosContent parseFromData:plaintextData];
        DDLogInfo(@"%@ handling content: <Content: %@>", self.tag, [self descriptionForContent:content]);

        if (content.hasSyncMessage) {
            [self handleIncomingEnvelope:envelope withSyncMessage:content.syncMessage transaction:transaction];
        } else if (content.hasDataMessage) {
            [self handleIncomingEnvelope:envelope withDataMessage:content.dataMessage transaction:transaction];
        } else if (content.hasCallMessage) {
            [self handleIncomingEnvelope:envelope withCallMessage:content.callMessage];
        } else if (content.hasNullMessage) {
            DDLogInfo(@"%@ Received null message.", self.tag);
        } else if (content.hasReceiptMessage) {
            [self handleIncomingEnvelope:envelope withReceiptMessage:content.receiptMessage transaction:transaction];
        } else {
            DDLogWarn(@"%@ Ignoring envelope. Content with no known payload", self.tag);
        }
    } else if (envelope.hasLegacyMessage) { // DEPRECATED - Remove after all clients have been upgraded.
        OWSSignalServiceProtosDataMessage *dataMessage =
            [OWSSignalServiceProtosDataMessage parseFromData:plaintextData];
        DDLogInfo(@"%@ handling message: <DataMessage: %@ />", self.tag, [self descriptionForDataMessage:dataMessage]);

        [self handleIncomingEnvelope:envelope withDataMessage:dataMessage transaction:transaction];
    } else {
        OWSProdInfoWEnvelope([OWSAnalyticsEvents messageManagerErrorEnvelopeNoActionablePayload], envelope);
    }
}

- (void)handleIncomingEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
               withDataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(envelope);
    OWSAssert(dataMessage);
    OWSAssert(transaction);

    if ([dataMessage hasProfileKey]) {
        NSData *profileKey = [dataMessage profileKey];
        NSString *recipientId = envelope.source;
        if (profileKey.length == kAES256_KeyByteLength) {
            [self.profileManager setProfileKeyData:profileKey forRecipientId:recipientId];
        } else {
            OWSFail(
                @"Unexpected profile key length:%lu on message from:%@", (unsigned long)profileKey.length, recipientId);
        }
    }

    if (dataMessage.hasGroup) {
        TSGroupModel *emptyModelToFillOutId =
            [[TSGroupModel alloc] initWithTitle:nil memberIds:nil image:nil groupId:dataMessage.group.id];
        TSGroupThread *gThread = [TSGroupThread threadWithGroupModel:emptyModelToFillOutId transaction:transaction];
        BOOL unknownGroup = NO;
        if (gThread == nil && dataMessage.group.type != OWSSignalServiceProtosGroupContextTypeUpdate) {
            unknownGroup = YES;
        }
        if (unknownGroup) {
            if (dataMessage.group.type == OWSSignalServiceProtosGroupContextTypeRequestInfo) {
                DDLogInfo(
                    @"%@ Ignoring group info request for group I don't know about from: %@", self.tag, envelope.source);
                return;
            }

            // FIXME: https://github.com/WhisperSystems/Signal-iOS/issues/1340
            DDLogInfo(@"%@ Received message from group that I left or don't know about from: %@",
                self.tag,
                envelopeAddress(envelope));

            NSString *recipientId = envelope.source;

            TSThread *thread = [TSContactThread getOrCreateThreadWithContactId:recipientId transaction:transaction];

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
        [self handleEndSessionMessageWithEnvelope:envelope dataMessage:dataMessage transaction:transaction];
    } else if ((dataMessage.flags & OWSSignalServiceProtosDataMessageFlagsExpirationTimerUpdate) != 0) {
        [self handleExpirationTimerUpdateMessageWithEnvelope:envelope dataMessage:dataMessage transaction:transaction];
    } else if ((dataMessage.flags & OWSSignalServiceProtosDataMessageFlagsProfileKeyUpdate) != 0) {
        [self handleProfileKeyMessageWithEnvelope:envelope dataMessage:dataMessage];
    } else if (dataMessage.attachments.count > 0) {
        [self handleReceivedMediaWithEnvelope:envelope dataMessage:dataMessage transaction:transaction];
    } else {
        [self handleReceivedTextMessageWithEnvelope:envelope dataMessage:dataMessage transaction:transaction];
        if ([self isDataMessageGroupAvatarUpdate:dataMessage]) {
            DDLogVerbose(@"%@ Data message had group avatar attachment", self.tag);
            [self handleReceivedGroupAvatarUpdateWithEnvelope:envelope dataMessage:dataMessage transaction:transaction];
        }
    }
}

- (id<ProfileManagerProtocol>)profileManager
{
    return [TextSecureKitEnv sharedEnv].profileManager;
}

- (void)handleIncomingEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
            withReceiptMessage:(OWSSignalServiceProtosReceiptMessage *)receiptMessage
                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(envelope);
    OWSAssert(receiptMessage);
    OWSAssert(transaction);

    PBArray *messageTimestamps = receiptMessage.timestamp;
    NSMutableArray<NSNumber *> *sentTimestamps = [NSMutableArray new];
    for (int i = 0; i < messageTimestamps.count; i++) {
        UInt64 timestamp = [messageTimestamps uint64AtIndex:i];
        [sentTimestamps addObject:@(timestamp)];
    }

    switch (receiptMessage.type) {
        case OWSSignalServiceProtosReceiptMessageTypeDelivery:
            DDLogVerbose(@"%@ Processing receipt message with delivery receipts.", self.tag);
            [self processDeliveryReceiptsFromRecipientId:envelope.source
                                          sentTimestamps:sentTimestamps
                                       deliveryTimestamp:@(envelope.timestamp)
                                             transaction:transaction];
            return;
        case OWSSignalServiceProtosReceiptMessageTypeRead:
            DDLogVerbose(@"%@ Processing receipt message with read receipts.", self.tag);
            [OWSReadReceiptManager.sharedManager processReadReceiptsFromRecipientId:envelope.source
                                                                     sentTimestamps:sentTimestamps
                                                                      readTimestamp:envelope.timestamp];
            break;
        default:
            DDLogInfo(@"%@ Ignoring receipt message of unknown type: %d.", self.tag, (int)receiptMessage.type);
            return;
    }
}

- (void)handleIncomingEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
               withCallMessage:(OWSSignalServiceProtosCallMessage *)callMessage
{
    OWSAssert(envelope);
    OWSAssert(callMessage);

    if ([callMessage hasProfileKey]) {
        NSData *profileKey = [callMessage profileKey];
        NSString *recipientId = envelope.source;
        [self.profileManager setProfileKeyData:profileKey forRecipientId:recipientId];
    }

    // By dispatching async, we introduce the possibility that these messages might be lost
    // if the app exits before this block is executed.  This is fine, since the call by
    // definition will end if the app exits.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (callMessage.hasOffer) {
            [self.callMessageHandler receivedOffer:callMessage.offer fromCallerId:envelope.source];
        } else if (callMessage.hasAnswer) {
            [self.callMessageHandler receivedAnswer:callMessage.answer fromCallerId:envelope.source];
        } else if (callMessage.iceUpdate.count > 0) {
            for (OWSSignalServiceProtosCallMessageIceUpdate *iceUpdate in callMessage.iceUpdate) {
                [self.callMessageHandler receivedIceUpdate:iceUpdate fromCallerId:envelope.source];
            }
        } else if (callMessage.hasHangup) {
            DDLogVerbose(@"%@ Received CallMessage with Hangup.", self.tag);
            [self.callMessageHandler receivedHangup:callMessage.hangup fromCallerId:envelope.source];
        } else if (callMessage.hasBusy) {
            [self.callMessageHandler receivedBusy:callMessage.busy fromCallerId:envelope.source];
        } else {
            OWSProdInfoWEnvelope([OWSAnalyticsEvents messageManagerErrorCallMessageNoActionablePayload], envelope);
        }
    });
}

- (void)handleReceivedGroupAvatarUpdateWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                                        dataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
                                        transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(envelope);
    OWSAssert(dataMessage);
    OWSAssert(transaction);

    TSGroupThread *groupThread =
        [TSGroupThread getOrCreateThreadWithGroupIdData:dataMessage.group.id transaction:transaction];
    OWSAssert(groupThread);
    OWSAttachmentsProcessor *attachmentsProcessor =
        [[OWSAttachmentsProcessor alloc] initWithAttachmentProtos:@[ dataMessage.group.avatar ]
                                                        timestamp:envelope.timestamp
                                                            relay:envelope.relay
                                                           thread:groupThread
                                                   networkManager:self.networkManager
                                                   storageManager:self.storageManager
                                                      transaction:transaction];

    if (!attachmentsProcessor.hasSupportedAttachments) {
        DDLogWarn(@"%@ received unsupported group avatar envelope", self.tag);
        return;
    }
    [attachmentsProcessor fetchAttachmentsForMessage:nil
        transaction:transaction
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
                            transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(envelope);
    OWSAssert(dataMessage);
    OWSAssert(transaction);

    TSThread *thread = [self threadForEnvelope:envelope dataMessage:dataMessage transaction:transaction];
    OWSAssert(thread);
    OWSAttachmentsProcessor *attachmentsProcessor =
        [[OWSAttachmentsProcessor alloc] initWithAttachmentProtos:dataMessage.attachments
                                                        timestamp:envelope.timestamp
                                                            relay:envelope.relay
                                                           thread:thread
                                                   networkManager:self.networkManager
                                                   storageManager:self.storageManager
                                                      transaction:transaction];
    if (!attachmentsProcessor.hasSupportedAttachments) {
        DDLogWarn(@"%@ received unsupported media envelope", self.tag);
        return;
    }

    TSIncomingMessage *_Nullable createdMessage =
        [self handleReceivedEnvelope:envelope
                     withDataMessage:dataMessage
                       attachmentIds:attachmentsProcessor.supportedAttachmentIds
                         transaction:transaction];

    if (!createdMessage) {
        return;
    }

    DDLogDebug(@"%@ incoming attachment message: %@", self.tag, createdMessage.debugDescription);

    [attachmentsProcessor fetchAttachmentsForMessage:createdMessage
        transaction:transaction
        success:^(TSAttachmentStream *attachmentStream) {
            DDLogDebug(
                @"%@ successfully fetched attachment: %@ for message: %@", self.tag, attachmentStream, createdMessage);
        }
        failure:^(NSError *error) {
            DDLogError(
                @"%@ failed to fetch attachments for message: %@ with error: %@", self.tag, createdMessage, error);
        }];
}

- (void)handleIncomingEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
               withSyncMessage:(OWSSignalServiceProtosSyncMessage *)syncMessage
                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(envelope);
    OWSAssert(syncMessage);
    OWSAssert(transaction);
    OWSAssert([TSAccountManager isRegistered]);

    NSString *localNumber = [TSAccountManager localNumber];
    if (![localNumber isEqualToString:envelope.source]) {
        // Sync messages should only come from linked devices.
        OWSProdErrorWEnvelope([OWSAnalyticsEvents messageManagerErrorSyncMessageFromUnknownSource], envelope);
        return;
    }

    if (syncMessage.hasSent) {
        OWSIncomingSentMessageTranscript *transcript =
            [[OWSIncomingSentMessageTranscript alloc] initWithProto:syncMessage.sent relay:envelope.relay];

        OWSRecordTranscriptJob *recordJob =
            [[OWSRecordTranscriptJob alloc] initWithIncomingSentMessageTranscript:transcript];

        OWSSignalServiceProtosDataMessage *dataMessage = syncMessage.sent.message;
        OWSAssert(dataMessage);
        NSString *destination = syncMessage.sent.destination;
        if (dataMessage && destination.length > 0 && dataMessage.hasProfileKey) {
            // If we observe a linked device sending our profile key to another
            // user, we can infer that that user belongs in our profile whitelist.
            if (dataMessage.hasGroup) {
                [self.profileManager addGroupIdToProfileWhitelist:dataMessage.group.id];
            } else {
                [self.profileManager addUserToProfileWhitelist:destination];
            }
        }

        if ([self isDataMessageGroupAvatarUpdate:syncMessage.sent.message]) {
            [recordJob runWithAttachmentHandler:^(TSAttachmentStream *attachmentStream) {
                TSGroupThread *groupThread =
                    [TSGroupThread getOrCreateThreadWithGroupIdData:syncMessage.sent.message.group.id
                                                        transaction:transaction];
                [groupThread updateAvatarWithAttachmentStream:attachmentStream];
            }
                                    transaction:transaction];
        } else {
            [recordJob runWithAttachmentHandler:^(TSAttachmentStream *attachmentStream) {
                DDLogDebug(@"%@ successfully fetched transcript attachment: %@", self.tag, attachmentStream);
            }
                                    transaction:transaction];
        }
    } else if (syncMessage.hasRequest) {
        if (syncMessage.request.type == OWSSignalServiceProtosSyncMessageRequestTypeContacts) {
            OWSSyncContactsMessage *syncContactsMessage =
                [[OWSSyncContactsMessage alloc] initWithSignalAccounts:self.contactsManager.signalAccounts
                                                       identityManager:self.identityManager
                                                        profileManager:self.profileManager];
            DataSource *dataSource =
                [DataSourceValue dataSourceWithSyncMessage:[syncContactsMessage buildPlainTextAttachmentData]];
            [self.messageSender sendTemporaryAttachmentData:dataSource
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
            DataSource *dataSource =
                [DataSourceValue dataSourceWithSyncMessage:[syncGroupsMessage buildPlainTextAttachmentData]];
            [self.messageSender sendTemporaryAttachmentData:dataSource
                contentType:OWSMimeTypeApplicationOctetStream
                inMessage:syncGroupsMessage
                success:^{
                    DDLogInfo(@"%@ Successfully sent Groups response syncMessage.", self.tag);
                }
                failure:^(NSError *error) {
                    DDLogError(@"%@ Failed to send Groups response syncMessage with error: %@", self.tag, error);
                }];
        } else if (syncMessage.request.type == OWSSignalServiceProtosSyncMessageRequestTypeBlocked) {
            DDLogInfo(@"%@ Received request for block list", self.tag);
            [_blockingManager syncBlockedPhoneNumbers];
        } else if (syncMessage.request.type == OWSSignalServiceProtosSyncMessageRequestTypeConfiguration) {
            BOOL areReadReceiptsEnabled =
                [[OWSReadReceiptManager sharedManager] areReadReceiptsEnabledWithTransaction:transaction];
            OWSSyncConfigurationMessage *syncConfigurationMessage =
                [[OWSSyncConfigurationMessage alloc] initWithReadReceiptsEnabled:areReadReceiptsEnabled];
            [self.messageSender sendMessage:syncConfigurationMessage
                success:^{
                    DDLogInfo(@"%@ Successfully sent Configuration response syncMessage.", self.tag);
                }
                failure:^(NSError *error) {
                    DDLogError(@"%@ Failed to send Configuration response syncMessage with error: %@", self.tag, error);
                }];
        } else {
            DDLogWarn(@"%@ ignoring unsupported sync request message", self.tag);
        }
    } else if (syncMessage.hasBlocked) {
        NSArray<NSString *> *blockedPhoneNumbers = [syncMessage.blocked.numbers copy];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [_blockingManager setBlockedPhoneNumbers:blockedPhoneNumbers sendSyncMessage:NO];
        });
    } else if (syncMessage.read.count > 0) {
        DDLogInfo(@"%@ Received %ld read receipt(s)", self.tag, (u_long)syncMessage.read.count);

        [OWSReadReceiptManager.sharedManager processReadReceiptsFromLinkedDevice:syncMessage.read
                                                                     transaction:transaction];
    } else if (syncMessage.hasVerified) {
        DDLogInfo(@"%@ Received verification state for %@", self.tag, syncMessage.verified.destination);
        [self.identityManager processIncomingSyncMessage:syncMessage.verified];
    } else {
        DDLogWarn(@"%@ Ignoring unsupported sync message.", self.tag);
    }
}

- (void)handleEndSessionMessageWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                                dataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
                                transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(envelope);
    OWSAssert(dataMessage);
    OWSAssert(transaction);

    TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactId:envelope.source transaction:transaction];

    [[[TSInfoMessage alloc] initWithTimestamp:envelope.timestamp
                                     inThread:thread
                                  messageType:TSInfoMessageTypeSessionDidEnd] saveWithTransaction:transaction];

    dispatch_async([OWSDispatch sessionStoreQueue], ^{
        [self.storageManager deleteAllSessionsForContact:envelope.source];
    });
}

- (void)handleExpirationTimerUpdateMessageWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                                           dataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
                                           transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(envelope);
    OWSAssert(dataMessage);
    OWSAssert(transaction);

    TSThread *thread = [self threadForEnvelope:envelope dataMessage:dataMessage transaction:transaction];

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
    OWSAssert(disappearingMessagesConfiguration);
    [disappearingMessagesConfiguration saveWithTransaction:transaction];
    NSString *name = [self.contactsManager displayNameForPhoneIdentifier:envelope.source];
    OWSDisappearingConfigurationUpdateInfoMessage *message =
        [[OWSDisappearingConfigurationUpdateInfoMessage alloc] initWithTimestamp:envelope.timestamp
                                                                          thread:thread
                                                                   configuration:disappearingMessagesConfiguration
                                                             createdByRemoteName:name];
    [message saveWithTransaction:transaction];
}

- (void)handleProfileKeyMessageWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                                dataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
{
    OWSAssert(envelope);
    OWSAssert(dataMessage);

    NSString *recipientId = envelope.source;
    if (!dataMessage.hasProfileKey) {
        OWSFail(@"%@ received profile key message without profile key from: %@", self.tag, envelopeAddress(envelope));
        return;
    }
    NSData *profileKey = dataMessage.profileKey;
    if (profileKey.length != kAES256_KeyByteLength) {
        OWSFail(@"%@ received profile key of unexpected length:%lu from:%@",
            self.tag,
            (unsigned long)profileKey.length,
            envelopeAddress(envelope));
        return;
    }

    id<ProfileManagerProtocol> profileManager = [TextSecureKitEnv sharedEnv].profileManager;
    [profileManager setProfileKeyData:profileKey forRecipientId:recipientId];
}

- (void)handleReceivedTextMessageWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                                  dataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
                                  transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(envelope);
    OWSAssert(dataMessage);
    OWSAssert(transaction);

    [self handleReceivedEnvelope:envelope withDataMessage:dataMessage attachmentIds:@[] transaction:transaction];
}

- (void)sendGroupUpdateForThread:(TSGroupThread *)gThread message:(TSOutgoingMessage *)message
{
    OWSAssert(gThread);
    OWSAssert(gThread.groupModel);
    OWSAssert(message);

    if (gThread.groupModel.groupImage) {
        NSData *data = UIImagePNGRepresentation(gThread.groupModel.groupImage);
        DataSource *_Nullable dataSource = [DataSourceValue dataSourceWithData:data fileExtension:@"png"];
        [self.messageSender sendAttachmentData:dataSource
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
                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(envelope);
    OWSAssert(dataMessage);
    OWSAssert(transaction);
    OWSAssert(dataMessage.group.type == OWSSignalServiceProtosGroupContextTypeRequestInfo);

    NSData *groupId = dataMessage.hasGroup ? dataMessage.group.id : nil;
    if (!groupId) {
        OWSFail(@"Group info request is missing group id.");
        return;
    }

    DDLogWarn(@"%@ Received 'Request Group Info' message for group: %@ from: %@", self.tag, groupId, envelope.source);

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

    [self sendGroupUpdateForThread:gThread message:message];
}

- (TSIncomingMessage *_Nullable)handleReceivedEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                                       withDataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
                                         attachmentIds:(NSArray<NSString *> *)attachmentIds
                                           transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(envelope);
    OWSAssert(dataMessage);
    OWSAssert(transaction);

    uint64_t timestamp = envelope.timestamp;
    NSString *body = dataMessage.body;
    NSData *groupId = dataMessage.hasGroup ? dataMessage.group.id : nil;

    __block TSIncomingMessage *_Nullable incomingMessage;
    __block TSThread *thread;

    // Do this outside of a transaction to avoid deadlock
    OWSAssert([TSAccountManager isRegistered]);
    NSString *localNumber = [TSAccountManager localNumber];

    if (dataMessage.group.type == OWSSignalServiceProtosGroupContextTypeRequestInfo) {
        [self handleGroupInfoRequest:envelope dataMessage:dataMessage transaction:transaction];
        return nil;
    }

    if (groupId) {
        NSMutableArray *uniqueMemberIds = [[[NSSet setWithArray:dataMessage.group.members] allObjects] mutableCopy];
        TSGroupModel *model = [[TSGroupModel alloc] initWithTitle:dataMessage.group.name
                                                        memberIds:uniqueMemberIds
                                                            image:nil
                                                          groupId:dataMessage.group.id];
        TSGroupThread *gThread = [TSGroupThread getOrCreateThreadWithGroupModel:model transaction:transaction];

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
                if (body.length == 0 && attachmentIds.count < 1) {
                    DDLogWarn(@"%@ ignoring empty incoming message from: %@ for group: %@ with timestamp: %lu",
                        self.tag,
                        envelopeAddress(envelope),
                        groupId,
                        (unsigned long)timestamp);
                } else {
                    DDLogDebug(@"%@ incoming message from: %@ for group: %@ with timestamp: %lu",
                        self.tag,
                        envelopeAddress(envelope),
                        groupId,
                        (unsigned long)timestamp);
                    incomingMessage = [[TSIncomingMessage alloc] initWithTimestamp:timestamp
                                                                          inThread:gThread
                                                                          authorId:envelope.source
                                                                    sourceDeviceId:envelope.sourceDevice
                                                                       messageBody:body
                                                                     attachmentIds:attachmentIds
                                                                  expiresInSeconds:dataMessage.expireTimer];

                    [incomingMessage saveWithTransaction:transaction];
                }
                break;
            }
            default: {
                DDLogWarn(@"%@ Ignoring unknown group message type: %d", self.tag, (int)dataMessage.group.type);
            }
        }

        thread = gThread;
    } else {
        if (body.length == 0 && attachmentIds.count < 1) {
            DDLogWarn(@"%@ ignoring empty incoming message from: %@ with timestamp: %lu",
                self.tag,
                envelopeAddress(envelope),
                (unsigned long)timestamp);
        } else {
            DDLogDebug(@"%@ incoming message from: %@ with timestamp: %lu",
                self.tag,
                envelopeAddress(envelope),
                (unsigned long)timestamp);
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

            [incomingMessage saveWithTransaction:transaction];
            thread = cThread;
        }
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
        if ([attachmentIds count] > 0 && body != nil && body.length > 0) {
            // We want the text to be displayed under the attachment.
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

    if (thread && incomingMessage) {
        // In case we already have a read receipt for this new message (this happens sometimes).
        [OWSReadReceiptManager.sharedManager applyEarlyReadReceiptsForIncomingMessage:incomingMessage
                                                                          transaction:transaction];

        [OWSDisappearingMessagesJob becomeConsistentWithConfigurationForMessage:incomingMessage
                                                                contactsManager:self.contactsManager];

        // Update thread preview in inbox
        [thread touchWithTransaction:transaction];

        [[TextSecureKitEnv sharedEnv].notificationsManager notifyUserForIncomingMessage:incomingMessage
                                                                               inThread:thread
                                                                        contactsManager:self.contactsManager
                                                                            transaction:transaction];
    }

    return incomingMessage;
}

#pragma mark - helpers

- (BOOL)isDataMessageGroupAvatarUpdate:(OWSSignalServiceProtosDataMessage *)dataMessage
{
    return dataMessage.hasGroup && dataMessage.group.type == OWSSignalServiceProtosGroupContextTypeUpdate
        && dataMessage.group.hasAvatar;
}

/**
 * @returns
 *   Group or Contact thread for message, creating a new one if necessary.
 */
- (TSThread *)threadForEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                    dataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
                    transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(envelope);
    OWSAssert(dataMessage);
    OWSAssert(transaction);

    if (dataMessage.hasGroup) {
        return [TSGroupThread getOrCreateThreadWithGroupIdData:dataMessage.group.id transaction:transaction];
    } else {
        return [TSContactThread getOrCreateThreadWithContactId:envelope.source transaction:transaction];
    }
}

- (NSUInteger)unreadMessagesCount
{
    __block NSUInteger numberOfItems;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        numberOfItems = [[transaction ext:TSUnreadDatabaseViewExtensionName] numberOfItemsInAllGroups];
    }];

    return numberOfItems;
}

- (NSUInteger)unreadMessagesCountExcept:(TSThread *)thread
{
    __block NSUInteger numberOfItems;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        id databaseView = [transaction ext:TSUnreadDatabaseViewExtensionName];
        OWSAssert(databaseView);
        numberOfItems = ([databaseView numberOfItemsInAllGroups] - [databaseView numberOfItemsInGroup:thread.uniqueId]);
    }];

    return numberOfItems;
}

- (void)updateApplicationBadgeCount
{
    NSUInteger numberOfItems = [self unreadMessagesCount];
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:numberOfItems];
}

- (NSUInteger)unreadMessagesInThread:(TSThread *)thread
{
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
