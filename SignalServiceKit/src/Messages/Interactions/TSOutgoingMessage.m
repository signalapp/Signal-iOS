//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"
#import "NSDate+OWS.h"
#import "NSString+SSK.h"
#import "OWSContact.h"
#import "OWSMessageSender.h"
#import "OWSOutgoingSyncMessage.h"
#import "OWSPrimaryStorage.h"
#import "ProtoUtils.h"
#import "SignalRecipient.h"
#import "TSAccountManager.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TSQuotedMessage.h"
#import "TextSecureKitEnv.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

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
            OWSAssert(self.recipientStateMap);
        }
    }

    return self;
}

- (void)migrateRecipientStateMapWithCoder:(NSCoder *)coder
{
    OWSAssert(!self.recipientStateMap);
    OWSAssert(coder);

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
        OWSFail(@"%@ unexpected single group recipient message.", self.logTag);
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
            OWSAssert(!isGroupThread);
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
    static YapDatabaseConnection *connection = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        connection = [[OWSPrimaryStorage sharedManager] newDatabaseConnection];
    });
    return connection;
}

+ (instancetype)outgoingMessageInThread:(nullable TSThread *)thread
                            messageBody:(nullable NSString *)body
                           attachmentId:(nullable NSString *)attachmentId
{
    return [self outgoingMessageInThread:thread
                             messageBody:body
                            attachmentId:attachmentId
                        expiresInSeconds:0
                           quotedMessage:nil];
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
                           quotedMessage:nil];
}

+ (instancetype)outgoingMessageInThread:(nullable TSThread *)thread
                            messageBody:(nullable NSString *)body
                           attachmentId:(nullable NSString *)attachmentId
                       expiresInSeconds:(uint32_t)expiresInSeconds
                          quotedMessage:(nullable TSQuotedMessage *)quotedMessage
{
    NSMutableArray<NSString *> *attachmentIds = [NSMutableArray new];
    if (attachmentId) {
        [attachmentIds addObject:attachmentId];
    }

    return [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                              inThread:thread
                                                           messageBody:body
                                                         attachmentIds:attachmentIds
                                                      expiresInSeconds:expiresInSeconds
                                                       expireStartedAt:0
                                                        isVoiceMessage:NO
                                                      groupMetaMessage:TSGroupMessageUnspecified
                                                         quotedMessage:quotedMessage
                                                          contactShare:nil];
}

+ (instancetype)outgoingMessageInThread:(nullable TSThread *)thread
                       groupMetaMessage:(TSGroupMetaMessage)groupMetaMessage
                       expiresInSeconds:(uint32_t)expiresInSeconds;
{
    return [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                              inThread:thread
                                                           messageBody:nil
                                                         attachmentIds:[NSMutableArray new]
                                                      expiresInSeconds:expiresInSeconds
                                                       expireStartedAt:0
                                                        isVoiceMessage:NO
                                                      groupMetaMessage:groupMetaMessage
                                                         quotedMessage:nil
                                                          contactShare:nil];
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
                                    contactShare:(nullable OWSContact *)contactShare
{
    self = [super initMessageWithTimestamp:timestamp
                                  inThread:thread
                               messageBody:body
                             attachmentIds:attachmentIds
                          expiresInSeconds:expiresInSeconds
                           expireStartedAt:expireStartedAt
                             quotedMessage:quotedMessage
                              contactShare:contactShare];
    if (!self) {
        return self;
    }

    _hasSyncedTranscript = NO;

    if ([thread isKindOfClass:TSGroupThread.class]) {
        // Unless specified, we assume group messages are "Delivery" i.e. normal messages.
        if (groupMetaMessage == TSGroupMessageUnspecified) {
            _groupMetaMessage = TSGroupMessageDeliver;
        } else {
            _groupMetaMessage = groupMetaMessage;
        }
    } else {
        OWSAssert(groupMetaMessage == TSGroupMessageUnspecified);
        // Specifying a group meta message only makes sense for Group threads
        _groupMetaMessage = TSGroupMessageUnspecified;
    }

    _isVoiceMessage = isVoiceMessage;

    _attachmentFilenameMap = [NSMutableDictionary new];

    // New outgoing messages should immediately determine their
    // recipient list from current thread state.
    NSMutableDictionary<NSString *, TSOutgoingMessageRecipientState *> *recipientStateMap = [NSMutableDictionary new];
    NSArray<NSString *> *recipientIds;
    if ([self isKindOfClass:[OWSOutgoingSyncMessage class]]) {
        NSString *_Nullable localNumber = [TSAccountManager localNumber];
        OWSAssert(localNumber);
        recipientIds = @[
            localNumber,
        ];
    } else {
        recipientIds = [thread recipientIdentifiers];
    }
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
    [self.dbReadWriteConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (NSString *attachmentId in attachmentIds) {
            // We need to fetch each attachment, since [TSAttachment removeWithTransaction:] does important work.
            TSAttachment *_Nullable attachment =
                [TSAttachment fetchObjectWithUniqueID:attachmentId transaction:transaction];
            if (!attachment) {
                OWSCFail(@"%@ couldn't load interaction's attachment for deletion.", TSOutgoingMessage.logTag);
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

+ (TSOutgoingMessageState)messageStateForRecipientStates:(NSArray<TSOutgoingMessageRecipientState *> *)recipientStates
{
    OWSAssert(recipientStates);

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
    if (self.groupMetaMessage == TSGroupMessageDeliver || self.groupMetaMessage == TSGroupMessageUnspecified) {
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
        DDLogDebug(@"%@ Skipping save for group meta message.", self.logTag);

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
            DDLogWarn(@"%@ in %s expiration previously started", self.logTag, __PRETTY_FUNCTION__);
            
            return YES;
        }
        
        return NO;
    }
}

- (BOOL)isSilent
{
    return NO;
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
    OWSAssert(recipientId.length > 0);

    TSOutgoingMessageRecipientState *_Nullable result = self.recipientStateMap[recipientId];
    OWSAssert(result);
    return [result copy];
}

#pragma mark - Update With... Methods

- (void)updateWithSendingError:(NSError *)error
{
    OWSAssert(error);

    [self.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(TSOutgoingMessage *message) {
                                     // Mark any "sending" recipients as "failed."
                                     for (TSOutgoingMessageRecipientState *recipientState in message.recipientStateMap
                                              .allValues) {
                                         if (recipientState.state == OWSOutgoingMessageRecipientStateSending) {
                                             recipientState.state = OWSOutgoingMessageRecipientStateFailed;
                                         }
                                     }
                                     [message setMostRecentFailureText:error.localizedDescription];
                                 }];
    }];
}

- (void)updateWithAllSendingRecipientsMarkedAsFailedWithTansaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction);

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
    OWSAssert(transaction);

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
    OWSAssert(customMessage);
    OWSAssert(transaction);

    [self applyChangeToSelfAndLatestCopy:transaction
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

- (void)updateWithSentRecipient:(NSString *)recipientId transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(recipientId.length > 0);
    OWSAssert(transaction);

    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSOutgoingMessage *message) {
                                 TSOutgoingMessageRecipientState *_Nullable recipientState
                                     = message.recipientStateMap[recipientId];
                                 if (!recipientState) {
                                     OWSFail(@"%@ Missing recipient state for recipient: %@", self.logTag, recipientId);
                                     return;
                                 }
                                 recipientState.state = OWSOutgoingMessageRecipientStateSent;
                             }];
}

- (void)updateWithSkippedRecipient:(NSString *)recipientId transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(recipientId.length > 0);
    OWSAssert(transaction);

    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSOutgoingMessage *message) {
                                 TSOutgoingMessageRecipientState *_Nullable recipientState
                                     = message.recipientStateMap[recipientId];
                                 if (!recipientState) {
                                     OWSFail(@"%@ Missing recipient state for recipient: %@", self.logTag, recipientId);
                                     return;
                                 }
                                 recipientState.state = OWSOutgoingMessageRecipientStateSkipped;
                             }];
}

- (void)updateWithDeliveredRecipient:(NSString *)recipientId
                   deliveryTimestamp:(NSNumber *_Nullable)deliveryTimestamp
                         transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(recipientId.length > 0);
    OWSAssert(transaction);

    // If delivery notification doesn't include timestamp, use "now" as an estimate.
    if (!deliveryTimestamp) {
        deliveryTimestamp = @([NSDate ows_millisecondTimeStamp]);
    }

    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSOutgoingMessage *message) {
                                 TSOutgoingMessageRecipientState *_Nullable recipientState
                                     = message.recipientStateMap[recipientId];
                                 if (!recipientState) {
                                     OWSFail(@"%@ Missing recipient state for delivered recipient: %@",
                                         self.logTag,
                                         recipientId);
                                     return;
                                 }
                                 if (recipientState.state != OWSOutgoingMessageRecipientStateSent) {
                                     DDLogWarn(@"%@ marking unsent message as delivered.", self.logTag);
                                 }
                                 recipientState.state = OWSOutgoingMessageRecipientStateSent;
                                 recipientState.deliveryTimestamp = deliveryTimestamp;
                             }];
}

- (void)updateWithReadRecipientId:(NSString *)recipientId
                    readTimestamp:(uint64_t)readTimestamp
                      transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(recipientId.length > 0);
    OWSAssert(transaction);

    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSOutgoingMessage *message) {
                                 TSOutgoingMessageRecipientState *_Nullable recipientState
                                     = message.recipientStateMap[recipientId];
                                 if (!recipientState) {
                                     OWSFail(@"%@ Missing recipient state for delivered recipient: %@",
                                         self.logTag,
                                         recipientId);
                                     return;
                                 }
                                 if (recipientState.state != OWSOutgoingMessageRecipientStateSent) {
                                     DDLogWarn(@"%@ marking unsent message as delivered.", self.logTag);
                                 }
                                 recipientState.state = OWSOutgoingMessageRecipientStateSent;
                                 recipientState.readTimestamp = @(readTimestamp);
                             }];
}

- (void)updateWithWasSentFromLinkedDeviceWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction);

    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSOutgoingMessage *message) {
                                 // Mark any "sending" recipients as "sent."
                                 for (TSOutgoingMessageRecipientState *recipientState in message.recipientStateMap
                                          .allValues) {
                                     if (recipientState.state == OWSOutgoingMessageRecipientStateSending) {
                                         recipientState.state = OWSOutgoingMessageRecipientStateSent;
                                     }
                                 }
                                 [message setIsFromLinkedDevice:YES];
                             }];
}

- (void)updateWithSendingToSingleGroupRecipient:(NSString *)singleGroupRecipient
                                    transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction);
    OWSAssert(singleGroupRecipient.length > 0);

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
    OWSAssert(transaction);

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
                                             OWSFail(@"%@ unexpected message state.", self.logTag);
                                             break;
                                     }
                                 }
                             }];
}
#pragma mark -

- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilder
{
    TSThread *thread = self.thread;
    OWSAssert(thread);
    
    SSKProtoDataMessageBuilder *builder = [SSKProtoDataMessageBuilder new];
    [builder setTimestamp:self.timestamp];

    if ([self.body lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= kOversizeTextMessageSizeThreshold) {
        [builder setBody:self.body];
    } else {
        OWSFail(@"%@ message body length too long.", self.logTag);
        NSString *truncatedBody = [self.body copy];
        while ([truncatedBody lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > kOversizeTextMessageSizeThreshold) {
            DDLogError(@"%@ truncating body which is too long: %lu",
                self.logTag,
                (unsigned long)[truncatedBody lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
            truncatedBody = [truncatedBody substringToIndex:truncatedBody.length / 2];
        }
        [builder setBody:truncatedBody];
    }
    [builder setExpireTimer:self.expiresInSeconds];
    
    // Group Messages
    BOOL attachmentWasGroupAvatar = NO;
    if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *gThread = (TSGroupThread *)thread;
        SSKProtoGroupContextBuilder *groupBuilder = [SSKProtoGroupContextBuilder new];

        switch (self.groupMetaMessage) {
            case TSGroupMessageQuit:
                [groupBuilder setType:SSKProtoGroupContextTypeQuit];
                break;
            case TSGroupMessageUpdate:
            case TSGroupMessageNew: {
                if (gThread.groupModel.groupImage != nil && self.attachmentIds.count == 1) {
                    attachmentWasGroupAvatar = YES;
                    SSKProtoAttachmentPointer *_Nullable attachmentProto =
                        [TSAttachmentStream buildProtoForAttachmentId:self.attachmentIds.firstObject];
                    if (!attachmentProto) {
                        OWSFail(@"%@ could not build protobuf.", self.logTag);
                        return nil;
                    }
                    [groupBuilder setAvatar:attachmentProto];
                }

                [groupBuilder setMembers:gThread.groupModel.groupMemberIds];
                [groupBuilder setName:gThread.groupModel.groupName];
                [groupBuilder setType:SSKProtoGroupContextTypeUpdate];
                break;
            }
            default:
                [groupBuilder setType:SSKProtoGroupContextTypeDeliver];
                break;
        }
        [groupBuilder setId:gThread.groupModel.groupId];

        NSError *error;
        SSKProtoGroupContext *_Nullable groupContextProto = [groupBuilder buildAndReturnError:&error];
        if (error || !groupContextProto) {
            OWSFail(@"%@ could not build protobuf: %@.", self.logTag, error);
            return nil;
        }
        [builder setGroup:groupContextProto];
    }
    
    // Message Attachments
    if (!attachmentWasGroupAvatar) {
        NSMutableArray *attachments = [NSMutableArray new];
        for (NSString *attachmentId in self.attachmentIds) {
            SSKProtoAttachmentPointer *_Nullable attachmentProto =
                [TSAttachmentStream buildProtoForAttachmentId:attachmentId];
            if (!attachmentProto) {
                OWSFail(@"%@ could not build protobuf.", self.logTag);
                return nil;
            }
            [attachments addObject:attachmentProto];
        }
        [builder setAttachments:attachments];
    }

    // Quoted Reply
    SSKProtoDataMessageQuoteBuilder *_Nullable quotedMessageBuilder = self.quotedMessageBuilder;
    if (quotedMessageBuilder) {
        NSError *error;
        SSKProtoDataMessageQuote *_Nullable quoteProto = [quotedMessageBuilder buildAndReturnError:&error];
        if (error || !quoteProto) {
            OWSFail(@"%@ could not build protobuf: %@.", self.logTag, error);
            return nil;
        }
        [builder setQuote:quoteProto];
    }

    // Contact Share
    if (self.contactShare) {
        SSKProtoDataMessageContact *_Nullable contactProto =
            [OWSContacts protoForContact:self.contactShare];
        if (contactProto) {
            [builder addContact:contactProto];
        } else {
            OWSFail(@"%@ in %s contactProto was unexpectedly nil", self.logTag, __PRETTY_FUNCTION__);
        }
    }

    return builder;
}

- (nullable SSKProtoDataMessageQuoteBuilder *)quotedMessageBuilder
{
    if (!self.quotedMessage) {
        return nil;
    }
    TSQuotedMessage *quotedMessage = self.quotedMessage;

    SSKProtoDataMessageQuoteBuilder *quoteBuilder = [SSKProtoDataMessageQuoteBuilder new];
    [quoteBuilder setId:quotedMessage.timestamp];
    [quoteBuilder setAuthor:quotedMessage.authorId];

    BOOL hasQuotedText = NO;
    BOOL hasQuotedAttachment = NO;
    if (self.quotedMessage.body.length > 0) {
        hasQuotedText = YES;
        [quoteBuilder setText:quotedMessage.body];
    }

    if (quotedMessage.quotedAttachments) {
        for (OWSAttachmentInfo *attachment in quotedMessage.quotedAttachments) {
            hasQuotedAttachment = YES;

            SSKProtoDataMessageQuoteQuotedAttachmentBuilder *quotedAttachmentBuilder =
                [SSKProtoDataMessageQuoteQuotedAttachmentBuilder new];

            quotedAttachmentBuilder.contentType = attachment.contentType;
            quotedAttachmentBuilder.fileName = attachment.sourceFilename;
            if (attachment.thumbnailAttachmentStreamId) {
                quotedAttachmentBuilder.thumbnail =
                    [TSAttachmentStream buildProtoForAttachmentId:attachment.thumbnailAttachmentStreamId];
            }

            NSError *error;
            SSKProtoDataMessageQuoteQuotedAttachment *_Nullable quotedAttachmentMessage =
                [quotedAttachmentBuilder buildAndReturnError:&error];
            if (!quotedAttachmentMessage) {
                OWSFail(@"%@ could not build protobuf: %@", self.logTag, error);
                return nil;
            }

            [quoteBuilder addAttachments:quotedAttachmentMessage];
        }
    }

    if (hasQuotedText || hasQuotedAttachment) {
        return quoteBuilder;
    } else {
        OWSFail(@"%@ Invalid quoted message data.", self.logTag);
        return nil;
    }
}

// recipientId is nil when building "sent" sync messages for messages sent to groups.
- (nullable SSKProtoDataMessage *)buildDataMessage:(NSString *_Nullable)recipientId
{
    OWSAssert(self.thread);
    SSKProtoDataMessageBuilder *_Nullable builder = [self dataMessageBuilder];
    if (!builder) {
        OWSFail(@"%@ could not build protobuf.", self.logTag);
        return nil;
    }

    [ProtoUtils addLocalProfileKeyIfNecessary:self.thread recipientId:recipientId dataMessageBuilder:builder];

    NSError *error;
    SSKProtoDataMessage *_Nullable dataProto = [builder buildAndReturnError:&error];
    if (error || !dataProto) {
        OWSFail(@"%@ could not build protobuf: %@", self.logTag, error);
        return nil;
    }
    return dataProto;
}

- (nullable NSData *)buildPlainTextData:(SignalRecipient *)recipient
{
    NSError *error;
    SSKProtoDataMessage *_Nullable dataMessage = [self buildDataMessage:recipient.recipientId];
    if (!dataMessage) {
        OWSFail(@"%@ could not build protobuf: %@", self.logTag, error);
        return nil;
    }

    SSKProtoContentBuilder *contentBuilder = [SSKProtoContentBuilder new];
    [contentBuilder setDataMessage:dataMessage];
    SSKProtoContent *_Nullable contentProto = [contentBuilder buildAndReturnError:&error];
    if (error || !contentProto) {
        OWSFail(@"%@ could not build protobuf: %@", self.logTag, error);
        return nil;
    }
    NSData *_Nullable contentData = [contentProto serializedDataAndReturnError:&error];
    if (error || !contentData) {
        OWSFail(@"%@ could not serialize protobuf: %@", self.logTag, error);
        return nil;
    }
    return contentData;
}

- (BOOL)shouldSyncTranscript
{
    return !self.hasSyncedTranscript;
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

@end

NS_ASSUME_NONNULL_END
