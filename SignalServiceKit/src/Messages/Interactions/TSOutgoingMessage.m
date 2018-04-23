//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"
#import "NSDate+OWS.h"
#import "OWSMessageSender.h"
#import "OWSOutgoingSyncMessage.h"
#import "OWSSignalServiceProtos.pb.h"
#import "ProtoBuf+OWS.h"
#import "SignalRecipient.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TSQuotedMessage.h"
#import "TextSecureKitEnv.h"
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kTSOutgoingMessageSentRecipientAll = @"kTSOutgoingMessageSentRecipientAll";

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

@property (atomic, nullable) NSDictionary<NSString *, TSOutgoingMessageRecipientState *> *recipientStateMap;

@end

#pragma mark -

@implementation TSOutgoingMessage

- (instancetype)initWithCoder:(NSCoder *)coder
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
    // Our default recipient list is the current thread members.
    NSArray<NSString *> *recipientIds = [self.thread recipientIdentifiers];
    if (sentRecipients) {
        // If we have a `sentRecipients` list, prefer that as it is more accurate.
        recipientIds = sentRecipients;
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

    [self updateMessageState];
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
                                                         quotedMessage:quotedMessage];
}

+ (instancetype)outgoingMessageInThread:(nullable TSThread *)thread
                       groupMetaMessage:(TSGroupMetaMessage)groupMetaMessage
{
    return [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                              inThread:thread
                                                           messageBody:nil
                                                         attachmentIds:[NSMutableArray new]
                                                      expiresInSeconds:0
                                                       expireStartedAt:0
                                                        isVoiceMessage:NO
                                                      groupMetaMessage:groupMetaMessage
                                                         quotedMessage:nil];
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
{
    self = [super initMessageWithTimestamp:timestamp
                                  inThread:thread
                               messageBody:body
                             attachmentIds:attachmentIds
                          expiresInSeconds:expiresInSeconds
                           expireStartedAt:expireStartedAt
                             quotedMessage:quotedMessage];
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

    NSMutableDictionary<NSString *, TSOutgoingMessageRecipientState *> *recipientStateMap = [NSMutableDictionary new];
    NSArray<NSString *> *recipientIds = [self.thread recipientIdentifiers];
    for (NSString *recipientId in recipientIds) {
        TSOutgoingMessageRecipientState *recipientState = [TSOutgoingMessageRecipientState new];
        recipientState.state = OWSOutgoingMessageRecipientStateSending;
        recipientStateMap[recipientId] = recipientState;
    }
    self.recipientStateMap = [recipientStateMap copy];

    [self updateMessageState];

    return self;
}

- (void)updateMessageState
{
    //    self.messageState = [TSOutgoingMessage messageStateForRecipientStates:self.recipientStateMap.allValues];
}

- (TSOutgoingMessageState)messageState
{
    return [TSOutgoingMessage messageStateForRecipientStates:self.recipientStateMap.allValues];
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

- (OWSOutgoingMessageRecipientState)maxMessageState
{
    OWSOutgoingMessageRecipientState result = OWSOutgoingMessageRecipientStateMin;
    for (TSOutgoingMessageRecipientState *recipientState in self.recipientStateMap.allValues) {
        result = MAX(recipientState.state, result);
    }
    return result;
}

- (OWSOutgoingMessageRecipientState)minMessageState
{
    OWSOutgoingMessageRecipientState result = OWSOutgoingMessageRecipientStateMax;
    for (TSOutgoingMessageRecipientState *recipientState in self.recipientStateMap.allValues) {
        result = MIN(recipientState.state, result);
    }
    return result;
}

- (BOOL)shouldStartExpireTimer:(YapDatabaseReadTransaction *)transaction
{
    // It's not clear if we should wait until _all_ recipients have reached "sent or later"
    // (which could never occur if one group member is unregistered) or only wait until
    // the first recipient has reached "sent or later" (which could cause partially delivered
    // messages to expire).  For now, we'll do the latter.
    //
    // TODO: Revisit this decision.

    if (!self.isExpiringMessage) {
        return NO;
    } else if (self.recipientStateMap.count < 1) {
        return YES;
    } else {
        return self.maxMessageState >= OWSOutgoingMessageRecipientStateSent;
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
    return [self.recipientStateMap.allKeys copy];
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
    return result;
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
                                 [message updateMessageState];
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
                                 [message updateMessageState];
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

    // TODO: I suspect we're double-calling this method.

    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSOutgoingMessage *message) {
                                 TSOutgoingMessageRecipientState *_Nullable recipientState
                                     = message.recipientStateMap[recipientId];
                                 if (!recipientState) {
                                     OWSFail(@"%@ Missing recipient state for recipient: %@", self.logTag, recipientId);
                                     return;
                                 }
                                 recipientState.state = OWSOutgoingMessageRecipientStateSent;
                                 [message updateMessageState];
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
                                 [message updateMessageState];
                             }];
}

- (void)updateWithDeliveredRecipient:(NSString *)recipientId
                   deliveryTimestamp:(NSNumber *_Nullable)deliveryTimestamp
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
                                 recipientState.state = OWSOutgoingMessageRecipientStateSent;
                                 recipientState.deliveryTimestamp = deliveryTimestamp;
                                 [message updateMessageState];
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
                                 recipientState.state = OWSOutgoingMessageRecipientStateSent;
                                 recipientState.readTimestamp = @(readTimestamp);
                                 [message updateMessageState];
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
                                 [message updateMessageState];
                             }];
}

- (void)updateWithSingleGroupRecipient:(NSString *)singleGroupRecipient
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
                                 [message updateMessageState];
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
                                 [message updateMessageState];
                             }];
}
#pragma mark -

- (OWSSignalServiceProtosDataMessageBuilder *)dataMessageBuilder
{
    TSThread *thread = self.thread;
    OWSAssert(thread);
    
    OWSSignalServiceProtosDataMessageBuilder *builder = [OWSSignalServiceProtosDataMessageBuilder new];
    [builder setTimestamp:self.timestamp];


    if ([self.body lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= kOversizeTextMessageSizeThreshold) {
        [builder setBody:self.body];
    } else {
        OWSFail(@"%@ message body length too long.", self.logTag);
        NSString *truncatedBody = [self.body copy];
        while ([truncatedBody lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > kOversizeTextMessageSizeThreshold) {
            DDLogError(@"%@ truncating body which is too long: %tu",
                self.logTag,
                [truncatedBody lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
            truncatedBody = [truncatedBody substringToIndex:truncatedBody.length / 2];
        }
        [builder setBody:truncatedBody];
    }
    [builder setExpireTimer:self.expiresInSeconds];
    
    // Group Messages
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
                    [groupBuilder setAvatar:[self buildProtoForAttachmentId:self.attachmentIds[0] filename:nil]];
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
    
    // Message Attachments
    if (!attachmentWasGroupAvatar) {
        NSMutableArray *attachments = [NSMutableArray new];
        for (NSString *attachmentId in self.attachmentIds) {
            NSString *_Nullable sourceFilename = self.attachmentFilenameMap[attachmentId];
            [attachments addObject:[self buildProtoForAttachmentId:attachmentId filename:sourceFilename]];
        }
        [builder setAttachmentsArray:attachments];
    }
    
    // Quoted Attachment
    TSQuotedMessage *quotedMessage = self.quotedMessage;
    if (quotedMessage) {
        OWSSignalServiceProtosDataMessageQuoteBuilder *quoteBuilder = [OWSSignalServiceProtosDataMessageQuoteBuilder new];
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

                OWSSignalServiceProtosDataMessageQuoteQuotedAttachmentBuilder *quotedAttachmentBuilder = [OWSSignalServiceProtosDataMessageQuoteQuotedAttachmentBuilder new];
                
                quotedAttachmentBuilder.contentType = attachment.contentType;
                quotedAttachmentBuilder.fileName = attachment.sourceFilename;
                if (attachment.thumbnailAttachmentStreamId) {
                    quotedAttachmentBuilder.thumbnail =
                        [self buildProtoForAttachmentId:attachment.thumbnailAttachmentStreamId];
                }

                [quoteBuilder addAttachments:[quotedAttachmentBuilder build]];
            }
        }
        
        if (hasQuotedText || hasQuotedAttachment) {
            [builder setQuoteBuilder:quoteBuilder];
        } else {
            OWSFail(@"%@ Invalid quoted message data.", self.logTag);
        }
    }
    
    return builder;
}

// recipientId is nil when building "sent" sync messages for messages sent to groups.
- (OWSSignalServiceProtosDataMessage *)buildDataMessage:(NSString *_Nullable)recipientId
{
    OWSAssert(self.thread);
    OWSSignalServiceProtosDataMessageBuilder *builder = [self dataMessageBuilder];
    [builder addLocalProfileKeyIfNecessary:self.thread recipientId:recipientId];
    
    return [[self dataMessageBuilder] build];
}

- (NSData *)buildPlainTextData:(SignalRecipient *)recipient
{
    OWSSignalServiceProtosContentBuilder *contentBuilder = [OWSSignalServiceProtosContentBuilder new];
    contentBuilder.dataMessage = [self buildDataMessage:recipient.recipientId];
    return [[contentBuilder build] data];
}

- (BOOL)shouldSyncTranscript
{
    return !self.hasSyncedTranscript;
}

- (OWSSignalServiceProtosAttachmentPointer *)buildProtoForAttachmentId:(NSString *)attachmentId
{
    OWSAssert(attachmentId.length > 0);

    TSAttachment *attachment = [TSAttachmentStream fetchObjectWithUniqueID:attachmentId];
    if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
        DDLogError(@"Unexpected type for attachment builder: %@", attachment);
        return nil;
    }
    TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;
    return [self buildProtoForAttachmentStream:attachmentStream filename:attachmentStream.sourceFilename];
}

- (OWSSignalServiceProtosAttachmentPointer *)buildProtoForAttachmentId:(NSString *)attachmentId
                                                              filename:(nullable NSString *)filename
{
    OWSAssert(attachmentId.length > 0);

    TSAttachment *attachment = [TSAttachmentStream fetchObjectWithUniqueID:attachmentId];
    if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
        DDLogError(@"Unexpected type for attachment builder: %@", attachment);
        return nil;
    }
    TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;
    return [self buildProtoForAttachmentStream:attachmentStream filename:filename];
}

- (OWSSignalServiceProtosAttachmentPointer *)buildProtoForAttachmentStream:(TSAttachmentStream *)attachmentStream
                                                                  filename:(nullable NSString *)filename
{
    OWSSignalServiceProtosAttachmentPointerBuilder *builder = [OWSSignalServiceProtosAttachmentPointerBuilder new];
    [builder setId:attachmentStream.serverId];
    OWSAssert(attachmentStream.contentType.length > 0);
    [builder setContentType:attachmentStream.contentType];
    DDLogVerbose(@"%@ Sending attachment with filename: '%@'", self.logTag, filename);
    [builder setFileName:filename];
    [builder setSize:attachmentStream.byteCount];
    [builder setKey:attachmentStream.encryptionKey];
    [builder setDigest:attachmentStream.digest];
    [builder setFlags:(self.isVoiceMessage ? OWSSignalServiceProtosAttachmentPointerFlagsVoiceMessage : 0)];

    if ([attachmentStream shouldHaveImageSize]) {
        CGSize imageSize = [attachmentStream imageSize];
        if (imageSize.width < NSIntegerMax && imageSize.height < NSIntegerMax) {
            NSInteger imageWidth = (NSInteger)round(imageSize.width);
            NSInteger imageHeight = (NSInteger)round(imageSize.height);
            if (imageWidth > 0 && imageHeight > 0) {
                [builder setWidth:(UInt32)imageWidth];
                [builder setHeight:(UInt32)imageHeight];
            }
        }
    }

    return [builder build];
}

@end

NS_ASSUME_NONNULL_END
