//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSIncomingMessage.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSIncomingMessage ()

@property (nonatomic, getter=wasRead) BOOL read;
@property (nonatomic, getter=wasViewed) BOOL viewed;

@property (nonatomic, nullable) NSNumber *serverTimestamp;
@property (nonatomic, readonly) NSUInteger incomingMessageSchemaVersion;

@end

#pragma mark -

const NSUInteger TSIncomingMessageSchemaVersion = 1;

@implementation TSIncomingMessage

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    NSString *authorPhoneNumber = self.authorPhoneNumber;
    if (authorPhoneNumber != nil) {
        [coder encodeObject:authorPhoneNumber forKey:@"authorPhoneNumber"];
    }
    NSString *authorUUID = self.authorUUID;
    if (authorUUID != nil) {
        [coder encodeObject:authorUUID forKey:@"authorUUID"];
    }
    NSNumber *deprecated_sourceDeviceId = self.deprecated_sourceDeviceId;
    if (deprecated_sourceDeviceId != nil) {
        [coder encodeObject:deprecated_sourceDeviceId forKey:@"deprecated_sourceDeviceId"];
    }
    [coder encodeObject:[self valueForKey:@"incomingMessageSchemaVersion"] forKey:@"incomingMessageSchemaVersion"];
    [coder encodeObject:[self valueForKey:@"read"] forKey:@"read"];
    [coder encodeObject:[self valueForKey:@"serverDeliveryTimestamp"] forKey:@"serverDeliveryTimestamp"];
    NSString *serverGuid = self.serverGuid;
    if (serverGuid != nil) {
        [coder encodeObject:serverGuid forKey:@"serverGuid"];
    }
    NSNumber *serverTimestamp = self.serverTimestamp;
    if (serverTimestamp != nil) {
        [coder encodeObject:serverTimestamp forKey:@"serverTimestamp"];
    }
    [coder encodeObject:[self valueForKey:@"viewed"] forKey:@"viewed"];
    [coder encodeObject:[self valueForKey:@"wasReceivedByUD"] forKey:@"wasReceivedByUD"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_authorPhoneNumber = [coder decodeObjectOfClass:[NSString class] forKey:@"authorPhoneNumber"];
    self->_authorUUID = [coder decodeObjectOfClass:[NSString class] forKey:@"authorUUID"];
    self->_deprecated_sourceDeviceId = [coder decodeObjectOfClass:[NSNumber class] forKey:@"deprecated_sourceDeviceId"];
    self->_incomingMessageSchemaVersion =
        [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                         forKey:@"incomingMessageSchemaVersion"] unsignedIntegerValue];
    self->_read = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class] forKey:@"read"] boolValue];
    self->_serverDeliveryTimestamp =
        [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                         forKey:@"serverDeliveryTimestamp"] unsignedLongLongValue];
    self->_serverGuid = [coder decodeObjectOfClass:[NSString class] forKey:@"serverGuid"];
    self->_serverTimestamp = [coder decodeObjectOfClass:[NSNumber class] forKey:@"serverTimestamp"];
    self->_viewed = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class] forKey:@"viewed"] boolValue];
    self->_wasReceivedByUD = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                              forKey:@"wasReceivedByUD"] boolValue];

    if (_incomingMessageSchemaVersion < 1) {
        _authorPhoneNumber = [coder decodeObjectForKey:@"authorId"];
        if (_authorPhoneNumber == nil) {
            _authorPhoneNumber = [TSContactThread legacyContactPhoneNumberFromThreadId:self.uniqueThreadId];
        }
    }

    if (_authorUUID != nil) {
        _authorPhoneNumber = nil;
    }

    _incomingMessageSchemaVersion = TSIncomingMessageSchemaVersion;

    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.authorPhoneNumber.hash;
    result ^= self.authorUUID.hash;
    result ^= self.deprecated_sourceDeviceId.hash;
    result ^= self.incomingMessageSchemaVersion;
    result ^= self.read;
    result ^= self.serverDeliveryTimestamp;
    result ^= self.serverGuid.hash;
    result ^= self.serverTimestamp.hash;
    result ^= self.viewed;
    result ^= self.wasReceivedByUD;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    TSIncomingMessage *typedOther = (TSIncomingMessage *)other;
    if (![NSObject isObject:self.authorPhoneNumber equalToObject:typedOther.authorPhoneNumber]) {
        return NO;
    }
    if (![NSObject isObject:self.authorUUID equalToObject:typedOther.authorUUID]) {
        return NO;
    }
    if (![NSObject isObject:self.deprecated_sourceDeviceId equalToObject:typedOther.deprecated_sourceDeviceId]) {
        return NO;
    }
    if (self.incomingMessageSchemaVersion != typedOther.incomingMessageSchemaVersion) {
        return NO;
    }
    if (self.read != typedOther.read) {
        return NO;
    }
    if (self.serverDeliveryTimestamp != typedOther.serverDeliveryTimestamp) {
        return NO;
    }
    if (![NSObject isObject:self.serverGuid equalToObject:typedOther.serverGuid]) {
        return NO;
    }
    if (![NSObject isObject:self.serverTimestamp equalToObject:typedOther.serverTimestamp]) {
        return NO;
    }
    if (self.viewed != typedOther.viewed) {
        return NO;
    }
    if (self.wasReceivedByUD != typedOther.wasReceivedByUD) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    TSIncomingMessage *result = [super copyWithZone:zone];
    result->_authorPhoneNumber = self.authorPhoneNumber;
    result->_authorUUID = self.authorUUID;
    result->_deprecated_sourceDeviceId = self.deprecated_sourceDeviceId;
    result->_incomingMessageSchemaVersion = self.incomingMessageSchemaVersion;
    result->_read = self.read;
    result->_serverDeliveryTimestamp = self.serverDeliveryTimestamp;
    result->_serverGuid = self.serverGuid;
    result->_serverTimestamp = self.serverTimestamp;
    result->_viewed = self.viewed;
    result->_wasReceivedByUD = self.wasReceivedByUD;
    return result;
}

- (instancetype)initIncomingMessageWithBuilder:(TSIncomingMessageBuilder *)incomingMessageBuilder
{
    self = [super initMessageWithBuilder:incomingMessageBuilder];

    if (!self) {
        return self;
    }

    _authorUUID = incomingMessageBuilder.authorAciObjC.serviceIdUppercaseString;
    _authorPhoneNumber = incomingMessageBuilder.authorE164ObjC.stringValue;
    _deprecated_sourceDeviceId = nil;
    _read = incomingMessageBuilder.read;
    if (incomingMessageBuilder.serverTimestamp > 0) {
        _serverTimestamp = [NSNumber numberWithUnsignedLongLong:incomingMessageBuilder.serverTimestamp];
    } else {
        _serverTimestamp = nil;
    }
    _serverDeliveryTimestamp = incomingMessageBuilder.serverDeliveryTimestamp;
    _serverGuid = incomingMessageBuilder.serverGuid;
    _wasReceivedByUD = incomingMessageBuilder.wasReceivedByUD;

    _incomingMessageSchemaVersion = TSIncomingMessageSchemaVersion;

    return self;
}

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run
// `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
             receivedAtTimestamp:(uint64_t)receivedAtTimestamp
                          sortId:(uint64_t)sortId
                       timestamp:(uint64_t)timestamp
                  uniqueThreadId:(NSString *)uniqueThreadId
                            body:(nullable NSString *)body
                      bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                    contactShare:(nullable OWSContact *)contactShare
        deprecated_attachmentIds:(nullable NSArray<NSString *> *)deprecated_attachmentIds
                       editState:(TSEditState)editState
                 expireStartedAt:(uint64_t)expireStartedAt
              expireTimerVersion:(nullable NSNumber *)expireTimerVersion
                       expiresAt:(uint64_t)expiresAt
                expiresInSeconds:(unsigned int)expiresInSeconds
                       giftBadge:(nullable OWSGiftBadge *)giftBadge
               isGroupStoryReply:(BOOL)isGroupStoryReply
                          isPoll:(BOOL)isPoll
  isSmsMessageRestoredFromBackup:(BOOL)isSmsMessageRestoredFromBackup
              isViewOnceComplete:(BOOL)isViewOnceComplete
               isViewOnceMessage:(BOOL)isViewOnceMessage
                     linkPreview:(nullable OWSLinkPreview *)linkPreview
                  messageSticker:(nullable MessageSticker *)messageSticker
                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
    storedShouldStartExpireTimer:(BOOL)storedShouldStartExpireTimer
           storyAuthorUuidString:(nullable NSString *)storyAuthorUuidString
              storyReactionEmoji:(nullable NSString *)storyReactionEmoji
                  storyTimestamp:(nullable NSNumber *)storyTimestamp
              wasRemotelyDeleted:(BOOL)wasRemotelyDeleted
               authorPhoneNumber:(nullable NSString *)authorPhoneNumber
                      authorUUID:(nullable NSString *)authorUUID
       deprecated_sourceDeviceId:(nullable NSNumber *)deprecated_sourceDeviceId
                            read:(BOOL)read
         serverDeliveryTimestamp:(uint64_t)serverDeliveryTimestamp
                      serverGuid:(nullable NSString *)serverGuid
                 serverTimestamp:(nullable NSNumber *)serverTimestamp
                          viewed:(BOOL)viewed
                 wasReceivedByUD:(BOOL)wasReceivedByUD
{
    self = [super initWithGrdbId:grdbId
                        uniqueId:uniqueId
               receivedAtTimestamp:receivedAtTimestamp
                            sortId:sortId
                         timestamp:timestamp
                    uniqueThreadId:uniqueThreadId
                              body:body
                        bodyRanges:bodyRanges
                      contactShare:contactShare
          deprecated_attachmentIds:deprecated_attachmentIds
                         editState:editState
                   expireStartedAt:expireStartedAt
                expireTimerVersion:expireTimerVersion
                         expiresAt:expiresAt
                  expiresInSeconds:expiresInSeconds
                         giftBadge:giftBadge
                 isGroupStoryReply:isGroupStoryReply
                            isPoll:isPoll
    isSmsMessageRestoredFromBackup:isSmsMessageRestoredFromBackup
                isViewOnceComplete:isViewOnceComplete
                 isViewOnceMessage:isViewOnceMessage
                       linkPreview:linkPreview
                    messageSticker:messageSticker
                     quotedMessage:quotedMessage
      storedShouldStartExpireTimer:storedShouldStartExpireTimer
             storyAuthorUuidString:storyAuthorUuidString
                storyReactionEmoji:storyReactionEmoji
                    storyTimestamp:storyTimestamp
                wasRemotelyDeleted:wasRemotelyDeleted];

    if (!self) {
        return self;
    }

    if (authorUUID != nil) {
        _authorUUID = authorUUID;
    } else if (authorPhoneNumber != nil) {
        _authorPhoneNumber = authorPhoneNumber;
    }
    _deprecated_sourceDeviceId = deprecated_sourceDeviceId;
    _read = read;
    _serverDeliveryTimestamp = serverDeliveryTimestamp;
    _serverGuid = serverGuid;
    _serverTimestamp = serverTimestamp;
    _viewed = viewed;
    _wasReceivedByUD = wasReceivedByUD;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

- (OWSInteractionType)interactionType
{
    return OWSInteractionType_IncomingMessage;
}

#pragma mark - OWSReadTracking

// This method will be called after every insert and update, so it needs
// to be cheap.
- (BOOL)shouldStartExpireTimer
{
    if (self.hasPerConversationExpirationStarted) {
        // Expiration already started.
        return YES;
    } else if (!self.hasPerConversationExpiration) {
        return NO;
    } else {
        return self.wasRead && [super shouldStartExpireTimer];
    }
}

- (void)markAsReadAtTimestamp:(uint64_t)readTimestamp
                       thread:(TSThread *)thread
                 circumstance:(OWSReceiptCircumstance)circumstance
     shouldClearNotifications:(BOOL)shouldClearNotifications
                  transaction:(DBWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    if (self.read && readTimestamp >= self.expireStartedAt) {
        return;
    }

    [self anyUpdateIncomingMessageWithTransaction:transaction
                                            block:^(TSIncomingMessage *message) {
                                                message.read = YES;
                                                // No need to update MessageAttachmentReferences table;
                                                // this doesn's change isPastRevision state.
                                                if (self.editState == TSEditState_LatestRevisionUnread) {
                                                    message.editState = TSEditState_LatestRevisionRead;
                                                }
                                            }];

    // readTimestamp may be earlier than now, so backdate the expiration if necessary.
    [DisappearingMessagesExpirationJobObjcBridge startExpirationForMessage:self
                                                       expirationStartedAt:readTimestamp
                                                                        tx:transaction];

    [SSKEnvironment.shared.receiptManagerRef messageWasRead:self
                                                     thread:thread
                                               circumstance:circumstance
                                                transaction:transaction];

    if (shouldClearNotifications) {
        [NotificationPresenterObjC cancelNotificationsForMessageId:self.uniqueId];
    }
}

- (void)markAsViewedAtTimestamp:(uint64_t)viewedTimestamp
                         thread:(TSThread *)thread
                   circumstance:(OWSReceiptCircumstance)circumstance
                    transaction:(DBWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    if (self.viewed) {
        return;
    }

    [self anyUpdateIncomingMessageWithTransaction:transaction
                                            block:^(TSIncomingMessage *message) { message.viewed = YES; }];

    [SSKEnvironment.shared.receiptManagerRef messageWasViewed:self
                                                       thread:thread
                                                 circumstance:circumstance
                                                  transaction:transaction];
}

- (SignalServiceAddress *)authorAddress
{
    return [SignalServiceAddress legacyAddressWithServiceIdString:self.authorUUID phoneNumber:self.authorPhoneNumber];
}

@end

NS_ASSUME_NONNULL_END
