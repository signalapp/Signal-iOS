//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"
#import "NSDate+millisecondTimeStamp.h"
#import "OWSOutgoingSyncMessage.h"
#import "OWSSignalServiceProtos.pb.h"
#import "ProfileManagerProtocol.h"
#import "SignalRecipient.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TextSecureKitEnv.h"
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kTSOutgoingMessageSentRecipientAll = @"kTSOutgoingMessageSentRecipientAll";

@interface TSOutgoingMessage ()

@property (atomic) TSOutgoingMessageState messageState;
@property (atomic) BOOL hasSyncedTranscript;
@property (atomic) NSString *customMessage;
@property (atomic) NSString *mostRecentFailureText;
@property (atomic) BOOL wasDelivered;
@property (atomic) NSString *singleGroupRecipient;

// For outgoing, non-legacy group messages sent from this client, this
// contains the list of recipients to whom the message has been sent.
//
// This collection can also be tested to avoid repeat delivery to the
// same recipient.
@property (atomic) NSArray<NSString *> *sentRecipients;

@property (atomic) TSGroupMetaMessage groupMetaMessage;

@end

#pragma mark -

@implementation TSOutgoingMessage

@synthesize sentRecipients = _sentRecipients;

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];

    if (self) {
        if (!_attachmentFilenameMap) {
            _attachmentFilenameMap = [NSMutableDictionary new];
        }
        
        // Migrate message state.
        if (_messageState == TSOutgoingMessageStateSent_OBSOLETE) {
            _messageState = TSOutgoingMessageStateSentToService;
        } else if (_messageState == TSOutgoingMessageStateDelivered_OBSOLETE) {
            _messageState = TSOutgoingMessageStateSentToService;
            _wasDelivered = YES;
        }
        if (!_sentRecipients) {
            _sentRecipients = [NSArray new];
        }
    }

    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
{
    return [self initWithTimestamp:timestamp inThread:nil];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(nullable TSThread *)thread
{
    return [self initWithTimestamp:timestamp inThread:thread messageBody:nil];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
{
    return [self initWithTimestamp:timestamp
                          inThread:thread
                       messageBody:body
                     attachmentIds:[NSMutableArray new]
                  expiresInSeconds:0];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSMutableArray<NSString *> *)attachmentIds
{
    return [self initWithTimestamp:timestamp
                          inThread:thread
                       messageBody:body
                     attachmentIds:attachmentIds
                  expiresInSeconds:0];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSMutableArray<NSString *> *)attachmentIds
                 expiresInSeconds:(uint32_t)expiresInSeconds
{
    return [self initWithTimestamp:timestamp
                          inThread:thread
                       messageBody:body
                     attachmentIds:attachmentIds
                  expiresInSeconds:expiresInSeconds
                   expireStartedAt:0];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                   isVoiceMessage:(BOOL)isVoiceMessage
                 expiresInSeconds:(uint32_t)expiresInSeconds
{
    self = [self initWithTimestamp:timestamp
                          inThread:thread
                       messageBody:nil
                     attachmentIds:[NSMutableArray new]
                  expiresInSeconds:expiresInSeconds
                   expireStartedAt:0];
    if (self) {
        _isVoiceMessage = isVoiceMessage;
    }

    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSMutableArray<NSString *> *)attachmentIds
                 expiresInSeconds:(uint32_t)expiresInSeconds
                  expireStartedAt:(uint64_t)expireStartedAt
{
    TSGroupMetaMessage groupMetaMessage
        = ([thread isKindOfClass:[TSGroupThread class]] ? TSGroupMessageDeliver : TSGroupMessageNone);
    return [self initWithTimestamp:timestamp
                          inThread:thread
                       messageBody:body
                     attachmentIds:attachmentIds
                  expiresInSeconds:expiresInSeconds
                   expireStartedAt:expireStartedAt
                  groupMetaMessage:groupMetaMessage];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                 groupMetaMessage:(TSGroupMetaMessage)groupMetaMessage
{
    return [self initWithTimestamp:timestamp
                          inThread:thread
                       messageBody:@""
                     attachmentIds:[NSMutableArray new]
                  expiresInSeconds:0
                   expireStartedAt:0
                  groupMetaMessage:groupMetaMessage];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSMutableArray<NSString *> *)attachmentIds
                 expiresInSeconds:(uint32_t)expiresInSeconds
                  expireStartedAt:(uint64_t)expireStartedAt
                 groupMetaMessage:(TSGroupMetaMessage)groupMetaMessage
{
    self = [super initWithTimestamp:timestamp
                           inThread:thread
                        messageBody:body
                      attachmentIds:attachmentIds
                   expiresInSeconds:expiresInSeconds
                    expireStartedAt:expireStartedAt];
    if (!self) {
        return self;
    }

    _messageState = TSOutgoingMessageStateAttemptingOut;
    _sentRecipients = [NSArray new];
    _hasSyncedTranscript = NO;
    _groupMetaMessage = groupMetaMessage;

    _attachmentFilenameMap = [NSMutableDictionary new];

    return self;
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!(self.groupMetaMessage == TSGroupMessageDeliver || self.groupMetaMessage == TSGroupMessageNone)) {
        DDLogDebug(@"%@ Skipping save for group meta message.", self.tag);
        return;
    }

    [super saveWithTransaction:transaction];
}

- (nullable NSString *)recipientIdentifier
{
    return self.thread.contactIdentifier;
}

- (BOOL)shouldStartExpireTimer
{
    switch (self.messageState) {
        case TSOutgoingMessageStateSentToService:
            return self.isExpiringMessage;
        case TSOutgoingMessageStateAttemptingOut:
        case TSOutgoingMessageStateUnsent:
            return NO;
        case TSOutgoingMessageStateSent_OBSOLETE:
        case TSOutgoingMessageStateDelivered_OBSOLETE:
            OWSAssert(0);
            return self.isExpiringMessage;
    }
}

#pragma mark - Update Methods

// This method does the work for the "updateWith..." methods.  Please see
// the header for a discussion of those methods.
- (void)applyChangeToSelfAndLatestOutgoingMessage:(YapDatabaseReadWriteTransaction *)transaction
                                      changeBlock:(void (^)(TSOutgoingMessage *))changeBlock
{
    OWSAssert(transaction);

    changeBlock(self);

    NSString *collection = [[self class] collection];
    TSOutgoingMessage *latestMessage = [transaction objectForKey:self.uniqueId inCollection:collection];
    if (latestMessage) {
        changeBlock(latestMessage);
        [latestMessage saveWithTransaction:transaction];
    } else {
        // This message has not yet been saved.
        [self saveWithTransaction:transaction];
    }
}

- (void)updateWithSendingError:(NSError *)error
{
    OWSAssert(error);

    [self.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestOutgoingMessage:transaction
                                            changeBlock:^(TSOutgoingMessage *message) {
                                                [message setMessageState:TSOutgoingMessageStateUnsent];
                                                [message setMostRecentFailureText:error.localizedDescription];
                                            }];
    }];
}

- (void)updateWithMessageState:(TSOutgoingMessageState)messageState
{
    [self.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self updateWithMessageState:messageState transaction:transaction];
    }];
}

- (void)updateWithMessageState:(TSOutgoingMessageState)messageState
                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction);

    [self applyChangeToSelfAndLatestOutgoingMessage:transaction
                                        changeBlock:^(TSOutgoingMessage *message) {
                                            [message setMessageState:messageState];
                                        }];
}

- (void)updateWithHasSyncedTranscript:(BOOL)hasSyncedTranscript
{
    [self.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestOutgoingMessage:transaction
                                            changeBlock:^(TSOutgoingMessage *message) {
                                                [message setHasSyncedTranscript:hasSyncedTranscript];
                                            }];
    }];
}

- (void)updateWithCustomMessage:(NSString *)customMessage transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(customMessage);
    OWSAssert(transaction);

    [self applyChangeToSelfAndLatestOutgoingMessage:transaction
                                        changeBlock:^(TSOutgoingMessage *message) {
                                            [message setCustomMessage:customMessage];
                                        }];
}

- (void)updateWithCustomMessage:(NSString *)customMessage
{
    [self.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self updateWithCustomMessage:customMessage transaction:transaction];
    }];
}

- (void)updateWithWasDeliveredWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction);

    [self applyChangeToSelfAndLatestOutgoingMessage:transaction
                                        changeBlock:^(TSOutgoingMessage *message) {
                                            [message setWasDelivered:YES];
                                        }];
}

- (void)updateWithWasDelivered
{
    [self.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self updateWithWasDeliveredWithTransaction:transaction];
    }];
}

- (void)updateWithWasSentAndDelivered
{
    [self.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestOutgoingMessage:transaction
                                            changeBlock:^(TSOutgoingMessage *message) {
                                                [message setMessageState:TSOutgoingMessageStateSentToService];
                                                [message setWasDelivered:YES];
                                            }];
    }];
}

- (void)updateWithSingleGroupRecipient:(NSString *)singleGroupRecipient
                           transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction);
    OWSAssert(singleGroupRecipient.length > 0);

    [self applyChangeToSelfAndLatestOutgoingMessage:transaction
                                        changeBlock:^(TSOutgoingMessage *message) {
                                            [message setSingleGroupRecipient:singleGroupRecipient];
                                        }];
}

#pragma mark - Sent Recipients

- (NSArray<NSString *> *)sentRecipients
{
    @synchronized(self)
    {
        return _sentRecipients;
    }
}

- (void)setSentRecipients:(NSArray<NSString *> *)sentRecipients
{
    @synchronized(self)
    {
        _sentRecipients = [sentRecipients copy];
    }
}

- (void)addSentRecipient:(NSString *)contactId
{
    @synchronized(self)
    {
        OWSAssert(_sentRecipients);
        OWSAssert(contactId.length > 0);

        NSMutableArray *sentRecipients = [_sentRecipients mutableCopy];
        [sentRecipients addObject:contactId];
        _sentRecipients = [sentRecipients copy];
    }
}

- (BOOL)wasSentToRecipient:(NSString *)contactId
{
    OWSAssert(self.sentRecipients);
    OWSAssert(contactId.length > 0);

    return [self.sentRecipients containsObject:contactId];
}

- (NSUInteger)sentRecipientsCount
{
    OWSAssert(self.sentRecipients);

    return self.sentRecipients.count;
}

- (void)updateWithSentRecipient:(NSString *)contactId transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction);
    [self applyChangeToSelfAndLatestOutgoingMessage:transaction
                                        changeBlock:^(TSOutgoingMessage *message) {
                                            [message addSentRecipient:contactId];
                                        }];
}

- (void)updateWithSentRecipient:(NSString *)contactId
{
    [self.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self updateWithSentRecipient:contactId transaction:transaction];
    }];
}

#pragma mark -

- (OWSSignalServiceProtosDataMessageBuilder *)dataMessageBuilder
{
    TSThread *thread = self.thread;
    OWSSignalServiceProtosDataMessageBuilder *builder = [OWSSignalServiceProtosDataMessageBuilder new];
    [builder setBody:self.body];
    BOOL attachmentWasGroupAvatar = NO;
    if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *gThread = (TSGroupThread *)thread;
        OWSSignalServiceProtosGroupContextBuilder *groupBuilder = [OWSSignalServiceProtosGroupContextBuilder new];

        switch (self.groupMetaMessage) {
            case TSGroupMessageQuit:
                [groupBuilder setType:OWSSignalServiceProtosGroupContextTypeQuit];
                break;
            case TSGroupMessageUpdate:
            case TSGroupMessageNew: {
                if (gThread.groupModel.groupImage != nil && self.attachmentIds.count == 1) {
                    attachmentWasGroupAvatar = YES;
                    [groupBuilder
                        setAvatar:[self buildAttachmentProtoForAttachmentId:self.attachmentIds[0] filename:nil]];
                }

                [groupBuilder setMembersArray:gThread.groupModel.groupMemberIds];
                [groupBuilder setName:gThread.groupModel.groupName];
                [groupBuilder setType:OWSSignalServiceProtosGroupContextTypeUpdate];
                break;
            }
            default:
                [groupBuilder setType:OWSSignalServiceProtosGroupContextTypeDeliver];
                break;
        }
        [groupBuilder setId:gThread.groupModel.groupId];
        [builder setGroup:groupBuilder.build];
    }
    if (!attachmentWasGroupAvatar) {
        NSMutableArray *attachments = [NSMutableArray new];
        for (NSString *attachmentId in self.attachmentIds) {
            NSString *sourceFilename = self.attachmentFilenameMap[attachmentId];
            [attachments addObject:[self buildAttachmentProtoForAttachmentId:attachmentId filename:sourceFilename]];
        }
        [builder setAttachmentsArray:attachments];
    }
    [builder setExpireTimer:self.expiresInSeconds];
    return builder;
}

- (OWSSignalServiceProtosDataMessage *)buildDataMessage
{
    return [[self dataMessageBuilder] build];
}

- (void)addLocalProfileKeyIfNecessary:(OWSSignalServiceProtosContentBuilder *)contentBuilder
                            recipient:(SignalRecipient *)recipient
{
    OWSAssert(contentBuilder);
    OWSAssert(recipient);

    id<ProfileManagerProtocol> profileManager = [TextSecureKitEnv sharedEnv].profileManager;
    NSData *localProfileKey = profileManager.localProfileKey;

    OWSAssert(localProfileKey.length > 0);
    BOOL shouldIncludeProfileKey = NO;

    if ([self isKindOfClass:[OWSOutgoingSyncMessage class]]) {
        // Always sync the profile key to linked devices.
        shouldIncludeProfileKey = YES;
    } else {
        OWSAssert(self.thread);

        // For 1:1 threads, we want to include the profile key IFF the
        // contact is in the whitelist.
        //
        // For Group threads, we want to include the profile key IFF the
        // recipient OR the group is in the whitelist.
        if ([profileManager isUserInProfileWhitelist:recipient.recipientId]) {
            shouldIncludeProfileKey = YES;
        } else if ([profileManager isThreadInProfileWhitelist:self.thread]) {
            shouldIncludeProfileKey = YES;
        }
    }

    if (shouldIncludeProfileKey) {
        [contentBuilder setProfileKey:localProfileKey];
    }
}

- (NSData *)buildPlainTextData:(SignalRecipient *)recipient
{
    OWSSignalServiceProtosContentBuilder *contentBuilder = [OWSSignalServiceProtosContentBuilder new];
    contentBuilder.dataMessage = [self buildDataMessage];
    [self addLocalProfileKeyIfNecessary:contentBuilder recipient:recipient];
    return [[contentBuilder build] data];
}

- (BOOL)shouldSyncTranscript
{
    return !self.hasSyncedTranscript;
}

- (OWSSignalServiceProtosAttachmentPointer *)buildAttachmentProtoForAttachmentId:(NSString *)attachmentId
                                                                        filename:(nullable NSString *)filename
{
    OWSAssert(attachmentId.length > 0);

    TSAttachment *attachment = [TSAttachmentStream fetchObjectWithUniqueID:attachmentId];
    if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
        DDLogError(@"Unexpected type for attachment builder: %@", attachment);
        return nil;
    }
    TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;

    OWSSignalServiceProtosAttachmentPointerBuilder *builder = [OWSSignalServiceProtosAttachmentPointerBuilder new];
    [builder setId:attachmentStream.serverId];
    [builder setContentType:attachmentStream.contentType];
    [builder setFileName:filename];
    [builder setKey:attachmentStream.encryptionKey];
    [builder setDigest:attachmentStream.digest];
    [builder setFlags:(self.isVoiceMessage ? OWSSignalServiceProtosAttachmentPointerFlagsVoiceMessage : 0)];
    return [builder build];
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
