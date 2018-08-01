//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSReadReceiptsForSenderMessage.h"
#import "NSDate+OWS.h"
#import "SignalRecipient.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSReadReceiptsForSenderMessage ()

@property (nonatomic, readonly) NSArray<NSNumber *> *messageTimestamps;

@end

#pragma mark -

@implementation OWSReadReceiptsForSenderMessage

- (instancetype)initWithThread:(nullable TSThread *)thread messageTimestamps:(NSArray<NSNumber *> *)messageTimestamps
{
    self = [super initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                          inThread:thread
                                       messageBody:nil
                                     attachmentIds:[NSMutableArray new]
                                  expiresInSeconds:0
                                   expireStartedAt:0
                                    isVoiceMessage:NO
                                  groupMetaMessage:TSGroupMessageUnspecified
                                     quotedMessage:nil
                                      contactShare:nil];
    if (!self) {
        return self;
    }

    _messageTimestamps = [messageTimestamps copy];

    return self;
}

#pragma mark - TSOutgoingMessage overrides

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (BOOL)isSilent
{
    // Avoid "phantom messages" for "recipient read receipts".

    return YES;
}

- (nullable NSData *)buildPlainTextData:(SignalRecipient *)recipient
{
    OWSAssert(recipient);

    SSKProtoContentBuilder *contentBuilder = [SSKProtoContentBuilder new];
    [contentBuilder setReceiptMessage:[self buildReceiptMessage:recipient.recipientId]];
    return [[contentBuilder build] data];
}

- (SSKProtoReceiptMessage *)buildReceiptMessage:(NSString *)recipientId
{
    SSKProtoReceiptMessageBuilder *builder = [SSKProtoReceiptMessageBuilder new];

    [builder setType:SSKProtoReceiptMessageTypeRead];
    OWSAssert(self.messageTimestamps.count > 0);
    for (NSNumber *messageTimestamp in self.messageTimestamps) {
        [builder addTimestamp:[messageTimestamp unsignedLongLongValue]];
    }

    return [builder build];
}

#pragma mark - TSYapDatabaseObject overrides

- (BOOL)shouldBeSaved
{
    return NO;
}

- (NSString *)debugDescription
{
    return [NSString stringWithFormat:@"%@ with message timestamps: %lu", self.logTag, (unsigned long)self.messageTimestamps.count];
}

@end

NS_ASSUME_NONNULL_END
