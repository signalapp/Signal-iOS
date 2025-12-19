//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSReceiptsForSenderMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSReceiptsForSenderMessage ()

@property (nonatomic, readonly, nullable) NSSet<NSString *> *messageUniqueIds;
@property (nonatomic, readonly) NSArray<NSNumber *> *messageTimestamps;
@property (nonatomic, readonly) SSKProtoReceiptMessageType receiptType;

@end

#pragma mark -

@implementation OWSReceiptsForSenderMessage

+ (OWSReceiptsForSenderMessage *)deliveryReceiptsForSenderMessageWithThread:(TSThread *)thread
                                                                 receiptSet:(MessageReceiptSet *)receiptSet
                                                                transaction:(DBReadTransaction *)transaction
{
    return [[OWSReceiptsForSenderMessage alloc] initWithThread:thread
                                                    receiptSet:receiptSet
                                                   receiptType:SSKProtoReceiptMessageTypeDelivery
                                                   transaction:transaction];
}

+ (OWSReceiptsForSenderMessage *)readReceiptsForSenderMessageWithThread:(TSThread *)thread
                                                             receiptSet:(MessageReceiptSet *)receiptSet
                                                            transaction:(DBReadTransaction *)transaction
{
    return [[OWSReceiptsForSenderMessage alloc] initWithThread:thread
                                                    receiptSet:receiptSet
                                                   receiptType:SSKProtoReceiptMessageTypeRead
                                                   transaction:transaction];
}

+ (OWSReceiptsForSenderMessage *)viewedReceiptsForSenderMessageWithThread:(TSThread *)thread
                                                               receiptSet:(MessageReceiptSet *)receiptSet
                                                              transaction:(DBReadTransaction *)transaction
{
    return [[OWSReceiptsForSenderMessage alloc] initWithThread:thread
                                                    receiptSet:receiptSet
                                                   receiptType:SSKProtoReceiptMessageTypeViewed
                                                   transaction:transaction];
}

- (instancetype)initWithThread:(TSThread *)thread
                    receiptSet:(MessageReceiptSet *)receiptSet
                   receiptType:(SSKProtoReceiptMessageType)receiptType
                   transaction:(DBReadTransaction *)transaction
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder
                            additionalRecipients:@[]
                              explicitRecipients:@[]
                               skippedRecipients:@[]
                                     transaction:transaction];
    if (!self) {
        return self;
    }

    _messageUniqueIds = [receiptSet.uniqueIds copy];
    _messageTimestamps = [receiptSet.timestamps copy];
    _receiptType = receiptType;

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    NSArray *messageTimestamps = self.messageTimestamps;
    if (messageTimestamps != nil) {
        [coder encodeObject:messageTimestamps forKey:@"messageTimestamps"];
    }
    NSSet *messageUniqueIds = self.messageUniqueIds;
    if (messageUniqueIds != nil) {
        [coder encodeObject:messageUniqueIds forKey:@"messageUniqueIds"];
    }
    [coder encodeObject:[self valueForKey:@"receiptType"] forKey:@"receiptType"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_messageTimestamps = [coder decodeObjectOfClasses:[NSSet setWithArray:@[ [NSArray class], [NSNumber class] ]]
                                                     forKey:@"messageTimestamps"];
    self->_messageUniqueIds = [coder decodeObjectOfClasses:[NSSet setWithArray:@[ [NSSet class], [NSString class] ]]
                                                    forKey:@"messageUniqueIds"];
    self->_receiptType = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class] forKey:@"receiptType"] intValue];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.messageTimestamps.hash;
    result ^= self.messageUniqueIds.hash;
    result ^= (NSUInteger)self.receiptType;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    OWSReceiptsForSenderMessage *typedOther = (OWSReceiptsForSenderMessage *)other;
    if (![NSObject isObject:self.messageTimestamps equalToObject:typedOther.messageTimestamps]) {
        return NO;
    }
    if (![NSObject isObject:self.messageUniqueIds equalToObject:typedOther.messageUniqueIds]) {
        return NO;
    }
    if (self.receiptType != typedOther.receiptType) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSReceiptsForSenderMessage *result = [super copyWithZone:zone];
    result->_messageTimestamps = self.messageTimestamps;
    result->_messageUniqueIds = self.messageUniqueIds;
    result->_receiptType = self.receiptType;
    return result;
}

#pragma mark - TSOutgoingMessage overrides

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (BOOL)isUrgent
{
    return NO;
}

- (nullable SSKProtoContentBuilder *)contentBuilderWithThread:(TSThread *)thread
                                                  transaction:(DBReadTransaction *)transaction
{
    SSKProtoReceiptMessage *_Nullable receiptMessage = [self buildReceiptMessageWithTransaction:transaction];
    if (!receiptMessage) {
        OWSFailDebug(@"could not build protobuf.");
        return nil;
    }

    SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
    [contentBuilder setReceiptMessage:receiptMessage];
    return contentBuilder;
}

- (nullable SSKProtoReceiptMessage *)buildReceiptMessageWithTransaction:(DBReadTransaction *)transaction
{
    OWSAssertDebug(self.recipientAddresses.count == 1);
    OWSAssertDebug(self.messageTimestamps.count > 0);

    SSKProtoReceiptMessageBuilder *builder = [SSKProtoReceiptMessage builder];
    [builder setType:self.receiptType];
    for (NSNumber *messageTimestamp in self.messageTimestamps) {
        [builder addTimestamp:[messageTimestamp unsignedLongLongValue]];
    }

    return [builder buildInfallibly];
}

#pragma mark - TSYapDatabaseObject overrides

- (BOOL)shouldBeSaved
{
    return NO;
}

- (NSString *)debugDescription
{
    return [NSString
        stringWithFormat:@"[%@] with message timestamps: %lu", self.class, (unsigned long)self.messageTimestamps.count];
}

- (NSSet<NSString *> *)relatedUniqueIds
{
    if (self.messageUniqueIds) {
        return [[super relatedUniqueIds] setByAddingObjectsFromSet:self.messageUniqueIds];
    } else {
        return [super relatedUniqueIds];
    }
}

@end

NS_ASSUME_NONNULL_END
