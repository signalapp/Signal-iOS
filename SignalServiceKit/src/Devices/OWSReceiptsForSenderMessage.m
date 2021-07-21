//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/OWSReceiptsForSenderMessage.h>
#import <SignalServiceKit/SignalRecipient.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSReceiptsForSenderMessage ()

@property (nonatomic, readonly) NSArray<NSNumber *> *messageTimestamps;
@property (nonatomic, readonly) SSKProtoReceiptMessageType receiptType;

// The uniqueIds for the timestamps included in the receipt message
// Assembled when building the receipt proto. Not valid until then.
//
// We might want to consider initing the receipt message with the uniqueIds
// as well as the timestamp. That'll require a migrating change to our receipt store
// model. For now this should be fine.
@property (nonatomic, strong, nullable) NSArray<NSString *> *messageUniqueIds;

@end

#pragma mark -

@implementation OWSReceiptsForSenderMessage

+ (OWSReceiptsForSenderMessage *)deliveryReceiptsForSenderMessageWithThread:(TSThread *)thread
                                                          messageTimestamps:(NSArray<NSNumber *> *)messageTimestamps
{
    return [[OWSReceiptsForSenderMessage alloc] initWithThread:thread
                                             messageTimestamps:messageTimestamps
                                                   receiptType:SSKProtoReceiptMessageTypeDelivery];
}

+ (OWSReceiptsForSenderMessage *)readReceiptsForSenderMessageWithThread:(TSThread *)thread
                                                      messageTimestamps:(NSArray<NSNumber *> *)messageTimestamps
{
    return [[OWSReceiptsForSenderMessage alloc] initWithThread:thread
                                             messageTimestamps:messageTimestamps
                                                   receiptType:SSKProtoReceiptMessageTypeRead];
}

+ (OWSReceiptsForSenderMessage *)viewedReceiptsForSenderMessageWithThread:(TSThread *)thread
                                                        messageTimestamps:(NSArray<NSNumber *> *)messageTimestamps
{
    return [[OWSReceiptsForSenderMessage alloc] initWithThread:thread
                                             messageTimestamps:messageTimestamps
                                                   receiptType:SSKProtoReceiptMessageTypeViewed];
}

- (instancetype)initWithThread:(TSThread *)thread
             messageTimestamps:(NSArray<NSNumber *> *)messageTimestamps
                   receiptType:(SSKProtoReceiptMessageType)receiptType
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder];
    if (!self) {
        return self;
    }

    _messageTimestamps = [messageTimestamps copy];
    _receiptType = receiptType;

    return self;
}

#pragma mark - TSOutgoingMessage overrides

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (nullable NSData *)buildPlainTextData:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoReceiptMessage *_Nullable receiptMessage = [self buildReceiptMessageWithTransaction:transaction];
    if (!receiptMessage) {
        OWSFailDebug(@"could not build protobuf.");
        return nil;
    }

    SSKProtoContentBuilder *contentBuilder = [SSKProtoContent builder];
    [contentBuilder setReceiptMessage:receiptMessage];

    NSError *error;
    NSData *_Nullable contentData = [contentBuilder buildSerializedDataAndReturnError:&error];
    if (error || !contentData) {
        OWSFailDebug(@"could not serialize protobuf: %@", error);
        return nil;
    }
    return contentData;
}

- (nullable SSKProtoReceiptMessage *)buildReceiptMessageWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(self.recipientAddresses.count == 1);
    OWSAssertDebug(self.messageTimestamps.count > 0);
    NSError *_Nullable error = nil;
    NSMutableSet<NSString *> *messageUniqueIds = [[NSMutableSet alloc] init];

    SSKProtoReceiptMessageBuilder *builder = [SSKProtoReceiptMessage builder];
    [builder setType:self.receiptType];

    for (NSNumber *messageTimestamp in self.messageTimestamps) {
        [builder addTimestamp:[messageTimestamp unsignedLongLongValue]];

        NSArray<TSInteraction *> *interactions = [InteractionFinder
            interactionsWithTimestamp:messageTimestamp.unsignedLongLongValue
                               filter:^BOOL(TSInteraction *interaction) {
                                   if ([interaction isKindOfClass:[TSIncomingMessage class]]) {
                                       TSIncomingMessage *message = (TSIncomingMessage *)interaction;
                                       return
                                           [message.authorAddress isEqualToAddress:self.recipientAddresses.firstObject];
                                   } else {
                                       return NO;
                                   }
                               }
                          transaction:transaction
                                error:&error];

        OWSAssertDebug(interactions.count == 1);
        for (TSInteraction *interaction in interactions) {
            [messageUniqueIds addObject:interaction.uniqueId];
        }
    }
    self.messageUniqueIds = [messageUniqueIds copy];

    SSKProtoReceiptMessage *_Nullable receiptMessage = [builder buildAndReturnError:&error];
    if (error || !receiptMessage) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }
    return receiptMessage;
}

#pragma mark - TSYapDatabaseObject overrides

- (BOOL)shouldBeSaved
{
    return NO;
}

- (NSString *)debugDescription
{
    return [NSString
        stringWithFormat:@"%@ with message timestamps: %lu", self.logTag, (unsigned long)self.messageTimestamps.count];
}

- (NSSet<NSString *> *)relatedUniqueIds
{
    return [[super relatedUniqueIds] setByAddingObjectsFromArray:self.messageUniqueIds];
}

@end

NS_ASSUME_NONNULL_END
