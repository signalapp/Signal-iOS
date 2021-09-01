//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

@import Foundation;

#import "TSOutgoingMessage.h"
#import "TSDatabaseSecondaryIndexes.h"
#import "OWSPrimaryStorage.h"
#import "ProfileManagerProtocol.h"
#import "ProtoUtils.h"
#import "SSKEnvironment.h"
#import "SignalRecipient.h"
#import "TSAccountManager.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TSQuotedMessage.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseTransaction.h>
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

BOOL AreRecipientUpdatesEnabled(void)
{
    return NO;
}

NSString *const kTSOutgoingMessageSentRecipientAll = @"kTSOutgoingMessageSentRecipientAll";

NSString *NSStringForOutgoingMessageState(TSOutgoingMessageState value)
{
    switch (value) {
        case TSOutgoingMessageStateSending:
            return @"TSOutgoingMessageStateSending";
        case TSOutgoingMessageStateFailed:
            return @"TSOutgoingMessageStateFailed";
        case TSOutgoingMessageStateSent:
            return @"TSOutgoingMessageStateSent";
    }
}

NSString *NSStringForOutgoingMessageRecipientState(OWSOutgoingMessageRecipientState value)
{
    switch (value) {
        case OWSOutgoingMessageRecipientStateFailed:
            return @"OWSOutgoingMessageRecipientStateFailed";
        case OWSOutgoingMessageRecipientStateSending:
            return @"OWSOutgoingMessageRecipientStateSending";
        case OWSOutgoingMessageRecipientStateSkipped:
            return @"OWSOutgoingMessageRecipientStateSkipped";
        case OWSOutgoingMessageRecipientStateSent:
            return @"OWSOutgoingMessageRecipientStateSent";
    }
}

@interface TSOutgoingMessageRecipientState ()

@property (atomic) OWSOutgoingMessageRecipientState state;
@property (atomic, nullable) NSNumber *deliveryTimestamp;
@property (atomic, nullable) NSNumber *readTimestamp;
@property (atomic) BOOL wasSentByUD;

@end

#pragma mark -

@implementation TSOutgoingMessageRecipientState

@end

#pragma mark -

@interface TSOutgoingMessage ()

@property (atomic) BOOL hasSyncedTranscript;
@property (atomic) NSString *customMessage;
@property (atomic) NSString *mostRecentFailureText;
@property (atomic) TSGroupMetaMessage groupMetaMessage;
@property (atomic, nullable) NSDictionary<NSString *, TSOutgoingMessageRecipientState *> *recipientStateMap;

@end

#pragma mark -

@implementation TSOutgoingMessage

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];

    if (self) {
        if (!_attachmentFilenameMap) {
            _attachmentFilenameMap = [NSMutableDictionary new];
        }
    }

    return self;
}

+ (YapDatabaseConnection *)dbMigrationConnection
{
    return SSKEnvironment.shared.migrationDBConnection;
}

+ (instancetype)outgoingMessageInThread:(nullable TSThread *)thread
                            messageBody:(nullable NSString *)body
                           attachmentId:(nullable NSString *)attachmentId
{
    return [self outgoingMessageInThread:thread
                             messageBody:body
                            attachmentId:attachmentId
                        expiresInSeconds:0
                           quotedMessage:nil
                             linkPreview:nil];
}

+ (instancetype)outgoingMessageInThread:(nullable TSThread *)thread
                            messageBody:(nullable NSString *)body
                           attachmentId:(nullable NSString *)attachmentId
                       expiresInSeconds:(uint32_t)expiresInSeconds
{
    return [self outgoingMessageInThread:thread
                             messageBody:body
                            attachmentId:attachmentId
                        expiresInSeconds:expiresInSeconds
                           quotedMessage:nil
                             linkPreview:nil];
}

+ (instancetype)outgoingMessageInThread:(nullable TSThread *)thread
                            messageBody:(nullable NSString *)body
                           attachmentId:(nullable NSString *)attachmentId
                       expiresInSeconds:(uint32_t)expiresInSeconds
                          quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                            linkPreview:(nullable OWSLinkPreview *)linkPreview
{
    NSMutableArray<NSString *> *attachmentIds = [NSMutableArray new];
    if (attachmentId) {
        [attachmentIds addObject:attachmentId];
    }

    // MJK TODO remove SenderTimestamp?
    return [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                              inThread:thread
                                                           messageBody:body
                                                         attachmentIds:attachmentIds
                                                      expiresInSeconds:expiresInSeconds
                                                       expireStartedAt:0
                                                        isVoiceMessage:NO
                                                      groupMetaMessage:TSGroupMetaMessageUnspecified
                                                         quotedMessage:quotedMessage
                                                           linkPreview:linkPreview
                                               openGroupInvitationName:nil
                                                openGroupInvitationURL:nil
                                                            serverHash:nil];
}

+ (instancetype)outgoingMessageInThread:(nullable TSThread *)thread
                       groupMetaMessage:(TSGroupMetaMessage)groupMetaMessage
                       expiresInSeconds:(uint32_t)expiresInSeconds;
{
    // MJK TODO remove SenderTimestamp?
    return [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                              inThread:thread
                                                           messageBody:nil
                                                         attachmentIds:[NSMutableArray new]
                                                      expiresInSeconds:expiresInSeconds
                                                       expireStartedAt:0
                                                        isVoiceMessage:NO
                                                      groupMetaMessage:groupMetaMessage
                                                         quotedMessage:nil
                                                           linkPreview:nil
                                               openGroupInvitationName:nil
                                                openGroupInvitationURL:nil
                                                            serverHash:nil];
}

- (instancetype)initOutgoingMessageWithTimestamp:(uint64_t)timestamp
                                        inThread:(nullable TSThread *)thread
                                     messageBody:(nullable NSString *)body
                                   attachmentIds:(NSMutableArray<NSString *> *)attachmentIds
                                expiresInSeconds:(uint32_t)expiresInSeconds
                                 expireStartedAt:(uint64_t)expireStartedAt
                                  isVoiceMessage:(BOOL)isVoiceMessage
                                groupMetaMessage:(TSGroupMetaMessage)groupMetaMessage
                                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                                     linkPreview:(nullable OWSLinkPreview *)linkPreview
                         openGroupInvitationName:(nullable NSString *)openGroupInvitationName
                          openGroupInvitationURL:(nullable NSString *)openGroupInvitationURL
                                      serverHash:(nullable NSString *)serverHash
{
    self = [super initMessageWithTimestamp:timestamp
                                  inThread:thread
                               messageBody:body
                             attachmentIds:attachmentIds
                          expiresInSeconds:expiresInSeconds
                           expireStartedAt:expireStartedAt
                             quotedMessage:quotedMessage
                               linkPreview:linkPreview
                   openGroupInvitationName:openGroupInvitationName
                    openGroupInvitationURL:openGroupInvitationURL
                                serverHash:serverHash];
    if (!self) {
        return self;
    }

    _hasSyncedTranscript = NO;

    if ([thread isKindOfClass:TSGroupThread.class]) {
        // Unless specified, we assume group messages are "Delivery" i.e. normal messages.
        if (groupMetaMessage == TSGroupMetaMessageUnspecified) {
            _groupMetaMessage = TSGroupMetaMessageDeliver;
        } else {
            _groupMetaMessage = groupMetaMessage;
        }
    } else {
        // Specifying a group meta message only makes sense for Group threads
        _groupMetaMessage = TSGroupMetaMessageUnspecified;
    }

    _isVoiceMessage = isVoiceMessage;

    _attachmentFilenameMap = [NSMutableDictionary new];

    // New outgoing messages should immediately determine their
    // recipient list from current thread state.
    NSMutableDictionary<NSString *, TSOutgoingMessageRecipientState *> *recipientStateMap = [NSMutableDictionary new];
    NSArray<NSString *> *recipientIds = [thread recipientIdentifiers];
    for (NSString *recipientId in recipientIds) {
        TSOutgoingMessageRecipientState *recipientState = [TSOutgoingMessageRecipientState new];
        recipientState.state = OWSOutgoingMessageRecipientStateSending;
        recipientStateMap[recipientId] = recipientState;
    }
    self.recipientStateMap = [recipientStateMap copy];

    return self;
}

- (void)dealloc
{
    [self removeTemporaryAttachments];
}

// Each message has the responsibility for eagerly cleaning up its attachments.
// Normally this is done in [TSMessage removeWithTransaction], but that doesn't
// apply for "transient", unsaved messages (i.e. shouldBeSaved == NO).  These
// messages should clean up their attachments upon deallocation.
- (void)removeTemporaryAttachments
{
    if (self.shouldBeSaved) {
        // Message is not transient; no need to clean up attachments.
        return;
    }
    NSArray<NSString *> *_Nullable attachmentIds = self.attachmentIds;
    if (attachmentIds.count < 1) {
        return;
    }
    [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (NSString *attachmentId in attachmentIds) {
            // We need to fetch each attachment, since [TSAttachment removeWithTransaction:] does important work.
            TSAttachment *_Nullable attachment =
                [TSAttachment fetchObjectWithUniqueID:attachmentId transaction:transaction];
            if (!attachment) {
                continue;
            }
            [attachment removeWithTransaction:transaction];
        };
    }];
}

#pragma mark -

- (TSOutgoingMessageState)messageState
{
    return [TSOutgoingMessage messageStateForRecipientStates:self.recipientStateMap.allValues];
}

- (BOOL)wasDeliveredToAnyRecipient
{
    return [self deliveredRecipientIds].count > 0;
}

- (BOOL)wasSentToAnyRecipient
{
    return [self sentRecipientIds].count > 0;
}

+ (TSOutgoingMessageState)messageStateForRecipientStates:(NSArray<TSOutgoingMessageRecipientState *> *)recipientStates
{
    // If there are any "sending" recipients, consider this message "sending".
    BOOL hasFailed = NO;
    for (TSOutgoingMessageRecipientState *recipientState in recipientStates) {
        if (recipientState.state == OWSOutgoingMessageRecipientStateSending) {
            return TSOutgoingMessageStateSending;
        } else if (recipientState.state == OWSOutgoingMessageRecipientStateFailed) {
            hasFailed = YES;
        }
    }

    // If there are any "failed" recipients, consider this message "failed".
    if (hasFailed) {
        return TSOutgoingMessageStateFailed;
    }

    // Otherwise, consider the message "sent".
    //
    // NOTE: This includes messages with no recipients.
    return TSOutgoingMessageStateSent;
}

- (BOOL)shouldBeSaved
{
    if (self.groupMetaMessage == TSGroupMetaMessageDeliver || self.groupMetaMessage == TSGroupMetaMessageUnspecified) {
        return YES;
    }

    return NO;
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!self.shouldBeSaved) {
        // There's no need to save this message, since it's not displayed to the user.
        //
        // Should we find a need to save this in the future, we need to exclude any non-serializable properties.
        return;
    }

    [super saveWithTransaction:transaction];
}

- (BOOL)shouldStartExpireTimerWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    // It's not clear if we should wait until _all_ recipients have reached "sent or later"
    // (which could never occur if one group member is unregistered) or only wait until
    // the first recipient has reached "sent or later" (which could cause partially delivered
    // messages to expire).  For now, we'll do the latter.
    //
    // TODO: Revisit this decision.

    if (!self.isExpiringMessage) {
        return NO;
    } else if (self.messageState == TSOutgoingMessageStateSent) {
        return YES;
    } else {
        if (self.expireStartedAt > 0) {
            // Our initial migration to populate the recipient state map was incomplete. It's since been
            // addressed, but it's possible there are edge cases where a previously sent message would
            // no longer be considered sent.
            // So here we take extra care not to stop any expiration that had previously started.
            // This can also happen under normal cirumstances with an outgoing group message.
            return YES;
        }
        
        return NO;
    }
}

+ (nullable instancetype)findMessageWithTimestamp:(uint64_t)timestamp
{
    __block TSOutgoingMessage *result;
    [LKStorage readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [TSDatabaseSecondaryIndexes enumerateMessagesWithTimestamp:timestamp withBlock:^(NSString *collection, NSString *key, BOOL *stop) {
            TSInteraction *interaction = [TSInteraction fetchObjectWithUniqueID:key transaction:transaction];
            if ([interaction isKindOfClass:[TSOutgoingMessage class]]) {
                result = (TSOutgoingMessage *)interaction;
            }
        } usingTransaction:transaction];
    }];
    return result;
}

- (OWSInteractionType)interactionType
{
    return OWSInteractionType_OutgoingMessage;
}

- (NSArray<NSString *> *)recipientIds
{
    return self.recipientStateMap.allKeys;
}

- (NSArray<NSString *> *)sendingRecipientIds
{
    NSMutableArray<NSString *> *result = [NSMutableArray new];
    for (NSString *recipientId in self.recipientStateMap) {
        TSOutgoingMessageRecipientState *recipientState = self.recipientStateMap[recipientId];
        if (recipientState.state == OWSOutgoingMessageRecipientStateSending) {
            [result addObject:recipientId];
        }
    }
    return result;
}

- (NSArray<NSString *> *)sentRecipientIds
{
    NSMutableArray<NSString *> *result = [NSMutableArray new];
    for (NSString *recipientId in self.recipientStateMap) {
        TSOutgoingMessageRecipientState *recipientState = self.recipientStateMap[recipientId];
        if (recipientState.state == OWSOutgoingMessageRecipientStateSent) {
            [result addObject:recipientId];
        }
    }
    return result;
}

- (NSArray<NSString *> *)deliveredRecipientIds
{
    NSMutableArray<NSString *> *result = [NSMutableArray new];
    for (NSString *recipientId in self.recipientStateMap) {
        TSOutgoingMessageRecipientState *recipientState = self.recipientStateMap[recipientId];
        if (recipientState.deliveryTimestamp != nil) {
            [result addObject:recipientId];
        }
    }
    return result;
}

- (NSArray<NSString *> *)readRecipientIds
{
    NSMutableArray<NSString *> *result = [NSMutableArray new];
    for (NSString *recipientId in self.recipientStateMap) {
        TSOutgoingMessageRecipientState *recipientState = self.recipientStateMap[recipientId];
        if (recipientState.readTimestamp != nil) {
            [result addObject:recipientId];
        }
    }
    return result;
}

- (NSUInteger)sentRecipientsCount
{
    return [self.recipientStateMap.allValues
        filteredArrayUsingPredicate:[NSPredicate
                                        predicateWithBlock:^BOOL(TSOutgoingMessageRecipientState *recipientState,
                                            NSDictionary<NSString *, id> *_Nullable bindings) {
                                            return recipientState.state == OWSOutgoingMessageRecipientStateSent;
                                        }]]
        .count;
}

- (nullable TSOutgoingMessageRecipientState *)recipientStateForRecipientId:(NSString *)recipientId
{
    TSOutgoingMessageRecipientState *_Nullable result = self.recipientStateMap[recipientId];
    return [result copy];
}

#pragma mark - Update With... Methods

- (void)updateOpenGroupServerID:(uint64_t)openGroupServerID serverTimeStamp:(uint64_t)timestamp
{
    self.openGroupServerMessageID = openGroupServerID;
    [super updateTimestamp:timestamp];
}

- (void)updateWithSendingError:(NSError *)error transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSOutgoingMessage *message) {
                                 // Mark any "sending" recipients as "failed."
                                 for (TSOutgoingMessageRecipientState *recipientState in message.recipientStateMap.allValues) {
                                     if (recipientState.state == OWSOutgoingMessageRecipientStateSending) {
                                         recipientState.state = OWSOutgoingMessageRecipientStateFailed;
                                     }
                                 }
                                 [message setMostRecentFailureText:error.localizedDescription];
                             }];
}

- (void)updateWithAllSendingRecipientsMarkedAsFailedWithTansaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSOutgoingMessage *message) {
                                 // Mark any "sending" recipients as "failed."
                                 for (TSOutgoingMessageRecipientState *recipientState in message.recipientStateMap
                                          .allValues) {
                                     if (recipientState.state == OWSOutgoingMessageRecipientStateSending) {
                                         recipientState.state = OWSOutgoingMessageRecipientStateFailed;
                                     }
                                 }
                             }];
}

- (void)updateWithMarkingAllUnsentRecipientsAsSendingWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSOutgoingMessage *message) {
                                 // Mark any "sending" recipients as "failed."
                                 for (TSOutgoingMessageRecipientState *recipientState in message.recipientStateMap
                                          .allValues) {
                                     if (recipientState.state == OWSOutgoingMessageRecipientStateFailed) {
                                         recipientState.state = OWSOutgoingMessageRecipientStateSending;
                                     }
                                 }
                             }];
}

- (void)updateWithCustomMessage:(NSString *)customMessage transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSOutgoingMessage *message) {
                                 [message setCustomMessage:customMessage];
                             }];
}

- (void)updateWithCustomMessage:(NSString *)customMessage
{
    [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self updateWithCustomMessage:customMessage transaction:transaction];
    }];
}

- (void)updateWithSentRecipient:(NSString *)recipientId
                    wasSentByUD:(BOOL)wasSentByUD
                    transaction:(YapDatabaseReadWriteTransaction *)transaction {
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSOutgoingMessage *message) {
                                 TSOutgoingMessageRecipientState *_Nullable recipientState
                                     = message.recipientStateMap[recipientId];
                                 if (!recipientState) { return; }
                                 recipientState.state = OWSOutgoingMessageRecipientStateSent;
                                 recipientState.wasSentByUD = wasSentByUD;
                             }];
}

- (void)updateWithSkippedRecipient:(NSString *)recipientId transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSOutgoingMessage *message) {
                                 TSOutgoingMessageRecipientState *_Nullable recipientState
                                     = message.recipientStateMap[recipientId];
                                 if (!recipientState) { return; }
                                 recipientState.state = OWSOutgoingMessageRecipientStateSkipped;
                             }];
}

- (void)updateWithDeliveredRecipient:(NSString *)recipientId
                   deliveryTimestamp:(NSNumber *_Nullable)deliveryTimestamp
                         transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    // If delivery notification doesn't include timestamp, use "now" as an estimate.
    if (!deliveryTimestamp) {
        deliveryTimestamp = @([NSDate ows_millisecondTimeStamp]);
    }

    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSOutgoingMessage *message) {
                                 TSOutgoingMessageRecipientState *_Nullable recipientState
                                     = message.recipientStateMap[recipientId];
                                 if (!recipientState) { return; }
                                 recipientState.state = OWSOutgoingMessageRecipientStateSent;
                                 recipientState.deliveryTimestamp = deliveryTimestamp;
                             }];
}

- (void)updateWithReadRecipientId:(NSString *)recipientId
                    readTimestamp:(uint64_t)readTimestamp
                      transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSOutgoingMessage *message) {
                                 TSOutgoingMessageRecipientState *_Nullable recipientState = message.recipientStateMap[recipientId];
                                 if (!recipientState) { return; }
                                 recipientState.state = OWSOutgoingMessageRecipientStateSent;
                                 recipientState.readTimestamp = @(readTimestamp);
                             }];
}

#pragma mark - Delete

- (void)updateForDeletionWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [super updateForDeletionWithTransaction:transaction];
    [self removeWithTransaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
