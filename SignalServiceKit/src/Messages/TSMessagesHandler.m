//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSMessagesHandler.h"
//#import "ContactsManagerProtocol.h"
//#import "ContactsUpdater.h"
//#import "Cryptography.h"
//#import "DataSource.h"
//#import "MimeTypeUtil.h"
//#import "NSData+messagePadding.h"
//#import "NSDate+millisecondTimeStamp.h"
//#import "NotificationsProtocol.h"
//#import "OWSAttachmentsProcessor.h"
//#import "OWSBlockingManager.h"
//#import "OWSCallMessageHandler.h"
//#import "OWSDisappearingConfigurationUpdateInfoMessage.h"
//#import "OWSDisappearingMessagesConfiguration.h"
//#import "OWSDisappearingMessagesJob.h"
//#import "OWSError.h"
//#import "OWSIncomingMessageFinder.h"
//#import "OWSIncomingSentMessageTranscript.h"
//#import "OWSMessageSender.h"
//#import "OWSReadReceiptsProcessor.h"
//#import "OWSRecordTranscriptJob.h"
//#import "OWSSyncContactsMessage.h"
//#import "OWSSyncGroupsMessage.h"
//#import "OWSSyncGroupsRequestMessage.h"
//#import "ProfileManagerProtocol.h"
//#import "TSAccountManager.h"
//#import "TSErrorMessage.h"
//#import "TSPreKeyManager.h"
//#import "TSStorageManager.h"
//#import "TSStorageManager+SessionStore.h"
//#import "OWSAnalytics.h"
//#import "OWSIdentityManager.h"
#import "OWSSignalServiceProtos.pb.h"
//#import "TSAttachmentStream.h"
//#import "TSCall.h"
//#import "TSContactThread.h"
//#import "TSDatabaseView.h"
//#import "TSGroupModel.h"
//#import "TSGroupThread.h"
//#import "TSInfoMessage.h"
//#import "TSInvalidIdentityKeyReceivingErrorMessage.h"
//#import "TSNetworkManager.h"
//#import "TSStorageHeaders.h"
//#import "TextSecureKitEnv.h"
//#import <AxolotlKit/AxolotlExceptions.h>
//#import <AxolotlKit/SessionCipher.h>

NS_ASSUME_NONNULL_BEGIN

// used in log formatting
NSString *envelopeAddress(OWSSignalServiceProtosEnvelope *envelope)
{
    return [NSString stringWithFormat:@"%@.%d", envelope.source, (unsigned int)envelope.sourceDevice];
}

//// We need to use a consistent batch size throughout
//// the incoming message pipeline (i.e. in the
//// "decrypt" and "process" steps), or the pipeline
//// doesn't flow smoothly.
////
//// We want a value that is just high enough to yield
//// perf benefits.  The right value is probably 5-15.
// const NSUInteger kIncomingMessageBatchSize = 10;

@interface TSMessagesHandler ()

////@property (nonatomic, readonly) id<OWSCallMessageHandler> callMessageHandler;
////@property (nonatomic, readonly) id<ContactsManagerProtocol> contactsManager;
//@property (nonatomic, readonly) TSStorageManager *storageManager;
//@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
////@property (nonatomic, readonly) OWSMessageSender *messageSender;
////@property (nonatomic, readonly) OWSIncomingMessageFinder *incomingMessageFinder;
////@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
//@property (nonatomic, readonly) OWSIdentityManager *identityManager;

@end

#pragma mark -

@implementation TSMessagesHandler

//+ (instancetype)sharedManager {
//    static TSMessagesHandler *sharedMyManager = nil;
//    static dispatch_once_t onceToken;
//    dispatch_once(&onceToken, ^{
//        sharedMyManager = [[self alloc] initDefault];
//    });
//    return sharedMyManager;
//}
//
//- (instancetype)initDefault
//{
//    // TODO:
//    TSStorageManager *storageManager = [TSStorageManager sharedManager];
//    OWSIdentityManager *identityManager = [OWSIdentityManager sharedManager];
//          return [self initWithStorageManager:storageManager
//                              identityManager:identityManager];
////    TSNetworkManager *networkManager = [TSNetworkManager sharedManager];
////    TSStorageManager *storageManager = [TSStorageManager sharedManager];
////    id<ContactsManagerProtocol> contactsManager = [TextSecureKitEnv sharedEnv].contactsManager;
////    id<OWSCallMessageHandler> callMessageHandler = [TextSecureKitEnv sharedEnv].callMessageHandler;
////    ContactsUpdater *contactsUpdater = [ContactsUpdater sharedUpdater];
////      OWSMessageSender *messageSender = [TextSecureKitEnv sharedEnv].messageSender;
////
////
////    return [self initWithNetworkManager:networkManager
////                         storageManager:storageManager
////                     callMessageHandler:callMessageHandler
////                        contactsManager:contactsManager
////                        contactsUpdater:contactsUpdater
////                        identityManager:identityManager
////                          messageSender:messageSender];
//}
//
//- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
////- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager
////                        storageManager:(TSStorageManager *)storageManager
////                    callMessageHandler:(id<OWSCallMessageHandler>)callMessageHandler
////                       contactsManager:(id<ContactsManagerProtocol>)contactsManager
////                       contactsUpdater:(ContactsUpdater *)contactsUpdater
//                       identityManager:(OWSIdentityManager *)identityManager
////                         messageSender:(OWSMessageSender *)messageSender
//{
//    self = [super init];
//
//    if (!self) {
//        return self;
//    }
//
//    _storageManager = storageManager;
////    _networkManager = networkManager;
////    _callMessageHandler = callMessageHandler;
////    _contactsManager = contactsManager;
////    _contactsUpdater = contactsUpdater;
//    _identityManager = identityManager;
////    _messageSender = messageSender;
//
//    _dbConnection = storageManager.newDatabaseConnection;
////    _incomingMessageFinder = [[OWSIncomingMessageFinder alloc] initWithDatabase:storageManager.database];
////    _blockingManager = [OWSBlockingManager sharedManager];
//
//    OWSSingletonAssert();
//
////    [self startObserving];
//
//    return self;
//}

//- (void)startObserving
//{
//    [[NSNotificationCenter defaultCenter] addObserver:self
//                                             selector:@selector(yapDatabaseModified:)
//                                                 name:YapDatabaseModifiedNotification
//                                               object:nil];
//}
//
//- (void)yapDatabaseModified:(NSNotification *)notification
//{
//    [self updateApplicationBadgeCount];
//}

#pragma mark - Debugging

- (NSString *)descriptionForEnvelopeType:(OWSSignalServiceProtosEnvelope *)envelope
{
    OWSAssert(envelope != nil);

    switch (envelope.type) {
        case OWSSignalServiceProtosEnvelopeTypeReceipt:
            return @"DeliveryReceipt";
        case OWSSignalServiceProtosEnvelopeTypeUnknown:
            // Shouldn't happen
            OWSProdFail([OWSAnalyticsEvents messageManagerErrorEnvelopeTypeUnknown]);
            return @"Unknown";
        case OWSSignalServiceProtosEnvelopeTypeCiphertext:
            return @"SignalEncryptedMessage";
        case OWSSignalServiceProtosEnvelopeTypeKeyExchange:
            // Unsupported
            OWSProdFail([OWSAnalyticsEvents messageManagerErrorEnvelopeTypeKeyExchange]);
            return @"KeyExchange";
        case OWSSignalServiceProtosEnvelopeTypePrekeyBundle:
            return @"PreKeyEncryptedMessage";
        default:
            // Shouldn't happen
            OWSProdFail([OWSAnalyticsEvents messageManagerErrorEnvelopeTypeOther]);
            return @"Other";
    }
}

- (NSString *)descriptionForEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
{
    OWSAssert(envelope != nil);

    return [NSString stringWithFormat:@"<Envelope type: %@, source: %@, timestamp: %llu content.length: %lu />",
                     [self descriptionForEnvelopeType:envelope],
                     envelopeAddress(envelope),
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
        [description appendString:@"(Group:YES) "];
    }

    if ((dataMessage.flags & OWSSignalServiceProtosDataMessageFlagsEndSession) != 0) {
        [description appendString:@"EndSession"];
    } else if ((dataMessage.flags & OWSSignalServiceProtosDataMessageFlagsExpirationTimerUpdate) != 0) {
        [description appendString:@"ExpirationTimerUpdate"];
    } else if ((dataMessage.flags & OWSSignalServiceProtosDataMessageFlagsProfileKey) != 0) {
        [description appendString:@"ProfileKey"];
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
