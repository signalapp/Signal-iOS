//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSReceiptsForSenderMessage.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalRecipient.h>
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
{
    return [[OWSReceiptsForSenderMessage alloc] initWithThread:thread
                                                    receiptSet:receiptSet
                                                   receiptType:SSKProtoReceiptMessageTypeDelivery];
}

+ (OWSReceiptsForSenderMessage *)readReceiptsForSenderMessageWithThread:(TSThread *)thread
                                                             receiptSet:(MessageReceiptSet *)receiptSet
{
    return [[OWSReceiptsForSenderMessage alloc] initWithThread:thread
                                                    receiptSet:receiptSet
                                                   receiptType:SSKProtoReceiptMessageTypeRead];
}

+ (OWSReceiptsForSenderMessage *)viewedReceiptsForSenderMessageWithThread:(TSThread *)thread
                                                               receiptSet:(MessageReceiptSet *)receiptSet
{
    return [[OWSReceiptsForSenderMessage alloc] initWithThread:thread
                                                    receiptSet:receiptSet
                                                   receiptType:SSKProtoReceiptMessageTypeViewed];
}

- (instancetype)initWithThread:(TSThread *)thread
                    receiptSet:(MessageReceiptSet *)receiptSet
                   receiptType:(SSKProtoReceiptMessageType)receiptType
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder];
    if (!self) {
        return self;
    }

    _messageUniqueIds = [receiptSet.uniqueIds copy];
    _messageTimestamps = [receiptSet.timestamps copy];
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

    SSKProtoReceiptMessageBuilder *builder = [SSKProtoReceiptMessage builder];
    [builder setType:self.receiptType];
    for (NSNumber *messageTimestamp in self.messageTimestamps) {
        [builder addTimestamp:[messageTimestamp unsignedLongLongValue]];
    }

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
    if (self.messageUniqueIds) {
        return [[super relatedUniqueIds] setByAddingObjectsFromSet:self.messageUniqueIds];
    } else {
        return [super relatedUniqueIds];
    }
}

@end

NS_ASSUME_NONNULL_END
