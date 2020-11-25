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
        case TSOutgoingMessageStateSent_OBSOLETE:
            return @"TSOutgoingMessageStateSent_OBSOLETE";
        case TSOutgoingMessageStateDelivered_OBSOLETE:
            return @"TSOutgoingMessageStateDelivered_OBSOLETE";
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
@property (atomic) BOOL isFromLinkedDevice;
@property (atomic) TSGroupMetaMessage groupMetaMessage;

@property (nonatomic, readonly) TSOutgoingMessageState legacyMessageState;
@property (nonatomic, readonly) BOOL legacyWasDelivered;
@property (nonatomic, readonly) BOOL hasLegacyMessageState;

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

        if (!self.recipientStateMap) {
            [self migrateRecipientStateMapWithCoder:coder];
        }
    }

    return self;
}

- (void)migrateRecipientStateMapWithCoder:(NSCoder *)coder
{
    // Determine the "overall message state."
    TSOutgoingMessageState oldMessageState = TSOutgoingMessageStateFailed;
    NSNumber *_Nullable messageStateValue = [coder decodeObjectForKey:@"messageState"];
    if (messageStateValue) {
        oldMessageState = (TSOutgoingMessageState)messageStateValue.intValue;
    }
    _hasLegacyMessageState = YES;
    _legacyMessageState = oldMessageState;

    OWSOutgoingMessageRecipientState defaultState;
    switch (oldMessageState) {
        case TSOutgoingMessageStateFailed:
            defaultState = OWSOutgoingMessageRecipientStateFailed;
            break;
        case TSOutgoingMessageStateSending:
            defaultState = OWSOutgoingMessageRecipientStateSending;
            break;
        case TSOutgoingMessageStateSent:
        case TSOutgoingMessageStateSent_OBSOLETE:
        case TSOutgoingMessageStateDelivered_OBSOLETE:
            // Convert legacy values.
            defaultState = OWSOutgoingMessageRecipientStateSent;
            break;
    }

    // Try to leverage the "per-recipient state."
    NSDictionary<NSString *, NSNumber *> *_Nullable recipientDeliveryMap =
        [coder decodeObjectForKey:@"recipientDeliveryMap"];
    NSDictionary<NSString *, NSNumber *> *_Nullable recipientReadMap = [coder decodeObjectForKey:@"recipientReadMap"];
    NSArray<NSString *> *_Nullable sentRecipients = [coder decodeObjectForKey:@"sentRecipients"];

    NSMutableDictionary<NSString *, TSOutgoingMessageRecipientState *> *recipientStateMap = [NSMutableDictionary new];
    __block BOOL isGroupThread = NO;
    // Our default recipient list is the current thread members.
    __block NSArray<NSString *> *recipientIds = @[];
    // To avoid deadlock while migrating these records, we use a dedicated
    // migration connection.  For legacy records (created more than ~9 months
    // before the migration), we need to infer the recipient list for this
    // message from the current thread membership.  This inference isn't
    // always accurate, so not using the same connection for both reads is
    // acceptable.
    [TSOutgoingMessage.dbMigrationConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        TSThread *thread = [self threadWithTransaction:transaction];
        recipientIds = [thread recipientIdentifiers];
        isGroupThread = [thread isGroupThread];
    }];

    NSNumber *_Nullable wasDelivered = [coder decodeObjectForKey:@"wasDelivered"];
    _legacyWasDelivered = wasDelivered && wasDelivered.boolValue;
    BOOL wasDeliveredToContact = NO;
    if (isGroupThread) {
        // If we have a `sentRecipients` list, prefer that as it is more accurate.
        if (sentRecipients) {
            recipientIds = sentRecipients;
        }
    } else {
        // Special-case messages in contact threads; if "was delivered", we know
        // it was delivered to the contact.
        wasDeliveredToContact = _legacyWasDelivered;
    }

    NSString *_Nullable singleGroupRecipient = [coder decodeObjectForKey:@"singleGroupRecipient"];
    if (singleGroupRecipient) {
        // If this is a "single group recipient message", treat it as such.
        recipientIds = @[
            singleGroupRecipient,
        ];
    }

    for (NSString *recipientId in recipientIds) {
        TSOutgoingMessageRecipientState *recipientState = [TSOutgoingMessageRecipientState new];

        NSNumber *_Nullable readTimestamp = recipientReadMap[recipientId];
        NSNumber *_Nullable deliveryTimestamp = recipientDeliveryMap[recipientId];
        if (readTimestamp) {
            // If we have a read timestamp for this recipient, mark it as read.
            recipientState.state = OWSOutgoingMessageRecipientStateSent;
            recipientState.readTimestamp = readTimestamp;
            // deliveryTimestamp might be nil here.
            recipientState.deliveryTimestamp = deliveryTimestamp;
        } else if (deliveryTimestamp) {
            // If we have a delivery timestamp for this recipient, mark it as delivered.
            recipientState.state = OWSOutgoingMessageRecipientStateSent;
            recipientState.deliveryTimestamp = deliveryTimestamp;
        } else if (wasDeliveredToContact) {
            recipientState.state = OWSOutgoingMessageRecipientStateSent;
            // Use message time as an estimate of delivery time.
            recipientState.deliveryTimestamp = @(self.timestamp);
        } else if ([sentRecipients containsObject:recipientId]) {
            // If this recipient is in `sentRecipients`, mark it as sent.
            recipientState.state = OWSOutgoingMessageRecipientStateSent;
        } else {
            // Use the default state for this message.
            recipientState.state = defaultState;
        }

        recipientStateMap[recipientId] = recipientState;
    }
    self.recipientStateMap = [recipientStateMap copy];
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
                                                           linkPreview:linkPreview];
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
                                                           linkPreview:nil];
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
{
    self = [super initMessageWithTimestamp:timestamp
                                  inThread:thread
                               messageBody:body
                             attachmentIds:attachmentIds
                          expiresInSeconds:expiresInSeconds
                           expireStartedAt:expireStartedAt
                             quotedMessage:quotedMessage
                               linkPreview:linkPreview];
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
    TSOutgoingMessageState newMessageState =
        [TSOutgoingMessage messageStateForRecipientStates:self.recipientStateMap.allValues];
    if (self.hasLegacyMessageState) {
        if (newMessageState == TSOutgoingMessageStateSent || self.legacyMessageState == TSOutgoingMessageStateSent) {
            return TSOutgoingMessageStateSent;
        }
    }
    return newMessageState;
}

- (BOOL)wasDeliveredToAnyRecipient
{
    if ([self deliveredRecipientIds].count > 0) {
        return YES;
    }
    return (self.hasLegacyMessageState && self.legacyWasDelivered && self.messageState == TSOutgoingMessageStateSent);
}

- (BOOL)wasSentToAnyRecipient
{
    if ([self sentRecipientIds].count > 0) {
        return YES;
    }
    return (self.hasLegacyMessageState && self.messageState == TSOutgoingMessageStateSent);
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

- (BOOL)isSilent
{
    return NO;
}

- (BOOL)isOnline
{
    return NO;
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

- (void)updateWithHasSyncedTranscript:(BOOL)hasSyncedTranscript
                          transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSOutgoingMessage *message) {
                                 [message setHasSyncedTranscript:hasSyncedTranscript];
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

- (void)updateWithWasSentFromLinkedDeviceWithUDRecipientIds:(nullable NSArray<NSString *> *)udRecipientIds
                                          nonUdRecipientIds:(nullable NSArray<NSString *> *)nonUdRecipientIds
                                               isSentUpdate:(BOOL)isSentUpdate
                                                transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self
        applyChangeToSelfAndLatestCopy:transaction
                           changeBlock:^(TSOutgoingMessage *message) {
                               if (udRecipientIds.count > 0 || nonUdRecipientIds.count > 0) {
                                   // If we have specific recipient info from the transcript,
                                   // build a new recipient state map.
                                   NSMutableDictionary<NSString *, TSOutgoingMessageRecipientState *> *recipientStateMap
                                       = [NSMutableDictionary new];
                                   for (NSString *recipientId in udRecipientIds) {
                                       if (recipientStateMap[recipientId]) {
                                           continue;
                                       }
                                       TSOutgoingMessageRecipientState *recipientState =
                                           [TSOutgoingMessageRecipientState new];
                                       recipientState.state = OWSOutgoingMessageRecipientStateSent;
                                       recipientState.wasSentByUD = YES;
                                       recipientStateMap[recipientId] = recipientState;
                                   }
                                   for (NSString *recipientId in nonUdRecipientIds) {
                                       if (recipientStateMap[recipientId]) {
                                           continue;
                                       }
                                       TSOutgoingMessageRecipientState *recipientState =
                                           [TSOutgoingMessageRecipientState new];
                                       recipientState.state = OWSOutgoingMessageRecipientStateSent;
                                       recipientState.wasSentByUD = NO;
                                       recipientStateMap[recipientId] = recipientState;
                                   }

                                   if (isSentUpdate) {
                                       // If this is a "sent update", make sure that:
                                       //
                                       // a) "Sent updates" should never remove any recipients.  We end up with the
                                       //    union of the existing and new recipients.
                                       // b) "Sent updates" should never downgrade the "recipient state" for any
                                       //    recipients.  Prefer existing "recipient state"; "sent updates" only
                                       //    add new recipients at the "sent" state.
                                       //
                                       // Therefore we retain all existing entries in the recipient state map.
                                       [recipientStateMap addEntriesFromDictionary:self.recipientStateMap];
                                   }

                                   [message setRecipientStateMap:recipientStateMap];
                               } else {
                                   // Otherwise assume this is a legacy message before UD was introduced, and mark
                                   // any "sending" recipient as "sent".  Note that this will apply to non-legacy
                                   // messages with no recipients.
                                   for (TSOutgoingMessageRecipientState *recipientState in message.recipientStateMap
                                            .allValues) {
                                       if (recipientState.state == OWSOutgoingMessageRecipientStateSending) {
                                           recipientState.state = OWSOutgoingMessageRecipientStateSent;
                                       }
                                   }
                               }
                               
                               if (!isSentUpdate) {
                                   [message setIsFromLinkedDevice:YES];
                               }
                           }];
}

- (void)updateWithSendingToSingleGroupRecipient:(NSString *)singleGroupRecipient
                                    transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSOutgoingMessage *message) {
                                 TSOutgoingMessageRecipientState *recipientState =
                                     [TSOutgoingMessageRecipientState new];
                                 recipientState.state = OWSOutgoingMessageRecipientStateSending;
                                 [message setRecipientStateMap:@{
                                     singleGroupRecipient : recipientState,
                                 }];
                             }];
}

- (nullable NSNumber *)firstRecipientReadTimestamp
{
    NSNumber *result = nil;
    for (TSOutgoingMessageRecipientState *recipientState in self.recipientStateMap.allValues) {
        if (!recipientState.readTimestamp) {
            continue;
        }
        if (!result || (result.unsignedLongLongValue > recipientState.readTimestamp.unsignedLongLongValue)) {
            result = recipientState.readTimestamp;
        }
    }
    return result;
}

- (void)updateWithFakeMessageState:(TSOutgoingMessageState)messageState
                       transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSOutgoingMessage *message) {
                                 for (TSOutgoingMessageRecipientState *recipientState in message.recipientStateMap
                                          .allValues) {
                                     switch (messageState) {
                                         case TSOutgoingMessageStateSending:
                                             recipientState.state = OWSOutgoingMessageRecipientStateSending;
                                             break;
                                         case TSOutgoingMessageStateFailed:
                                             recipientState.state = OWSOutgoingMessageRecipientStateFailed;
                                             break;
                                         case TSOutgoingMessageStateSent:
                                             recipientState.state = OWSOutgoingMessageRecipientStateSent;
                                             break;
                                         default:
                                             break;
                                     }
                                 }
                             }];
}

#pragma mark -

- (nullable id)dataMessageBuilder
{
    TSThread *thread = self.thread;

    SNProtoDataMessageBuilder *builder = [SNProtoDataMessage builder];
    [builder setTimestamp:self.timestamp];

    if ([self.body lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= kOversizeTextMessageSizeThreshold) {
        [builder setBody:self.body];
    } else {
        NSString *truncatedBody = [self.body copy];
        while ([truncatedBody lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > kOversizeTextMessageSizeThreshold) {
            truncatedBody = [truncatedBody substringToIndex:truncatedBody.length / 2];
        }
        [builder setBody:truncatedBody];
    }
    [builder setExpireTimer:self.expiresInSeconds];
    
    // Group Messages
    BOOL attachmentWasGroupAvatar = NO;
    if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *gThread = (TSGroupThread *)thread;
        SNProtoGroupContextType groupMessageType;
        switch (self.groupMetaMessage) {
            case TSGroupMetaMessageQuit:
                groupMessageType = SNProtoGroupContextTypeQuit;
                break;
            case TSGroupMetaMessageUpdate:
            case TSGroupMetaMessageNew:
                groupMessageType = SNProtoGroupContextTypeUpdate;
                break;
            default:
                groupMessageType = SNProtoGroupContextTypeDeliver;
                break;
        }
        SNProtoGroupContextBuilder *groupBuilder =
            [SNProtoGroupContext builderWithId:gThread.groupModel.groupId type:groupMessageType];
        if (groupMessageType == SNProtoGroupContextTypeUpdate) {
            if (gThread.groupModel.groupImage != nil && self.attachmentIds.count == 1) {
                attachmentWasGroupAvatar = YES;
                SNProtoAttachmentPointer *_Nullable attachmentProto =
                    [TSAttachmentStream buildProtoForAttachmentId:self.attachmentIds.firstObject];
                if (!attachmentProto) {
                    return nil;
                }
                [groupBuilder setAvatar:attachmentProto];
            }

            [groupBuilder setMembers:gThread.groupModel.groupMemberIds];
            [groupBuilder setName:gThread.groupModel.groupName];
            [groupBuilder setAdmins:gThread.groupModel.groupAdminIds];
        }
        NSError *error;
        SNProtoGroupContext *_Nullable groupContextProto = [groupBuilder buildAndReturnError:&error];
        if (error || !groupContextProto) {
            return nil;
        }
        [builder setGroup:groupContextProto];
    }
    
    // Message Attachments
    if (!attachmentWasGroupAvatar) {
        NSMutableArray *attachments = [NSMutableArray new];
        for (NSString *attachmentId in self.attachmentIds) {
            SNProtoAttachmentPointer *_Nullable attachmentProto =
                [TSAttachmentStream buildProtoForAttachmentId:attachmentId];
            if (!attachmentProto) {
                return nil;
            }
            [attachments addObject:attachmentProto];
        }
        [builder setAttachments:attachments];
    }

    // Quoted Reply
    SNProtoDataMessageQuoteBuilder *_Nullable quotedMessageBuilder = self.quotedMessageBuilder;
    if (quotedMessageBuilder) {
        NSError *error;
        SNProtoDataMessageQuote *_Nullable quoteProto = [quotedMessageBuilder buildAndReturnError:&error];
        if (error || !quoteProto) {
            return nil;
        }
        [builder setQuote:quoteProto];
    }

    // Link Preview
    if (self.linkPreview) {
        SNProtoDataMessagePreviewBuilder *previewBuilder =
            [SNProtoDataMessagePreview builderWithUrl:self.linkPreview.urlString];
        if (self.linkPreview.title.length > 0) {
            [previewBuilder setTitle:self.linkPreview.title];
        }
        if (self.linkPreview.imageAttachmentId) {
            SNProtoAttachmentPointer *_Nullable attachmentProto =
                [TSAttachmentStream buildProtoForAttachmentId:self.linkPreview.imageAttachmentId];
            if (!attachmentProto) {

            } else {
                [previewBuilder setImage:attachmentProto];
            }
        }

        NSError *error;
        SNProtoDataMessagePreview *_Nullable previewProto = [previewBuilder buildAndReturnError:&error];
        if (error || !previewProto) {

        } else {
            [builder addPreview:previewProto];
        }
    }

    return builder;
}

- (nullable SNProtoDataMessageQuoteBuilder *)quotedMessageBuilder
{
    if (!self.quotedMessage) {
        return nil;
    }
    TSQuotedMessage *quotedMessage = self.quotedMessage;

    SNProtoDataMessageQuoteBuilder *quoteBuilder =
        [SNProtoDataMessageQuote builderWithId:quotedMessage.timestamp author:quotedMessage.authorId];

    BOOL hasQuotedText = NO;
    BOOL hasQuotedAttachment = NO;
    if (self.quotedMessage.body.length > 0) {
        hasQuotedText = YES;
        [quoteBuilder setText:quotedMessage.body];
    }

    if (quotedMessage.quotedAttachments) {
        for (OWSAttachmentInfo *attachment in quotedMessage.quotedAttachments) {
            hasQuotedAttachment = YES;

            SNProtoDataMessageQuoteQuotedAttachmentBuilder *quotedAttachmentBuilder =
                [SNProtoDataMessageQuoteQuotedAttachment builder];

            quotedAttachmentBuilder.contentType = attachment.contentType;
            quotedAttachmentBuilder.fileName = attachment.sourceFilename;
            if (attachment.thumbnailAttachmentStreamId) {
                quotedAttachmentBuilder.thumbnail =
                    [TSAttachmentStream buildProtoForAttachmentId:attachment.thumbnailAttachmentStreamId];
            }

            NSError *error;
            SNProtoDataMessageQuoteQuotedAttachment *_Nullable quotedAttachmentMessage =
                [quotedAttachmentBuilder buildAndReturnError:&error];
            if (error || !quotedAttachmentMessage) {
                return nil;
            }

            [quoteBuilder addAttachments:quotedAttachmentMessage];
        }
    }

    if (hasQuotedText || hasQuotedAttachment) {
        return quoteBuilder;
    } else {
        return nil;
    }
}

// recipientId is nil when building "sent" sync messages for messages sent to groups.
- (nullable SNProtoDataMessage *)buildDataMessage:(NSString *_Nullable)recipientId
{
    SNProtoDataMessageBuilder *_Nullable builder = [self dataMessageBuilder];
    if (builder == nil) {
        return nil;
    }

    [ProtoUtils addLocalProfileKeyIfNecessary:self.thread recipientId:recipientId dataMessageBuilder:builder];

    id<ProfileManagerProtocol> profileManager = SSKEnvironment.shared.profileManager;
    NSString *displayName;
    NSString *masterPublicKey = [NSUserDefaults.standardUserDefaults stringForKey:@"masterDeviceHexEncodedPublicKey"];
    if (masterPublicKey != nil) {
        displayName = [profileManager profileNameForRecipientWithID:masterPublicKey];
    } else {
        displayName = profileManager.localProfileName;
    }
    NSString *profilePictureURL = profileManager.profilePictureURL;
    SNProtoDataMessageLokiProfileBuilder *profileBuilder = [SNProtoDataMessageLokiProfile builder];
    [profileBuilder setDisplayName:displayName];
    [profileBuilder setProfilePicture:profilePictureURL ?: @""];
    SNProtoDataMessageLokiProfile *profile = [profileBuilder buildAndReturnError:nil];
    [builder setProfile:profile];
    
    NSError *error;
    SNProtoDataMessage *_Nullable dataProto = [builder buildAndReturnError:&error];
    if (error != nil || dataProto == nil) {
        return nil;
    }
    return dataProto;
}

- (nullable id)prepareCustomContentBuilder:(SignalRecipient *)recipient {
    SNProtoDataMessage *_Nullable dataMessage = [self buildDataMessage:recipient.recipientId];

    if (dataMessage == nil) {
        return nil;
    }
    
    SNProtoContentBuilder *contentBuilder = SNProtoContent.builder;
    [contentBuilder setDataMessage:dataMessage];
    
    return contentBuilder;
}

- (nullable NSData *)buildPlainTextData:(SignalRecipient *)recipient
{
    SNProtoContentBuilder *contentBuilder = [self prepareCustomContentBuilder:recipient];

    NSError *error;
    NSData *_Nullable contentData = [contentBuilder buildSerializedDataAndReturnError:&error];
    if (error != nil || contentData == nil) {
        return nil;
    }
    
    return contentData;
}

- (BOOL)shouldSyncTranscript
{
    return YES;
}

- (NSString *)statusDescription
{
    NSMutableString *result = [NSMutableString new];
    [result appendFormat:@"[status: %@", NSStringForOutgoingMessageState(self.messageState)];
    for (NSString *recipientId in self.recipientStateMap) {
        TSOutgoingMessageRecipientState *recipientState = self.recipientStateMap[recipientId];
        [result appendFormat:@", %@: %@", recipientId, NSStringForOutgoingMessageRecipientState(recipientState.state)];
    }
    [result appendString:@"]"];
    return [result copy];
}

- (uint)ttl { return 2 * 24 * 60 * 60 * 1000; }

@end

NS_ASSUME_NONNULL_END
