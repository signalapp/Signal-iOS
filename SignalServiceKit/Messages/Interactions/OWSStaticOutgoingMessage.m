//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSStaticOutgoingMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSStaticOutgoingMessage ()

@property (nonatomic, readonly) NSData *plaintextData;

@end

#pragma mark -

@implementation OWSStaticOutgoingMessage

- (instancetype)initWithThread:(TSThread *)thread
                     timestamp:(uint64_t)timestamp
                 plaintextData:(NSData *)plaintextData
                   transaction:(DBReadTransaction *)transaction
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    messageBuilder.timestamp = timestamp;
    self = [super initOutgoingMessageWithBuilder:messageBuilder
                            additionalRecipients:@[]
                              explicitRecipients:@[]
                               skippedRecipients:@[]
                                     transaction:transaction];

    if (self) {
        _plaintextData = plaintextData;
    }

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    NSData *plaintextData = self.plaintextData;
    if (plaintextData != nil) {
        [coder encodeObject:plaintextData forKey:@"plaintextData"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_plaintextData = [coder decodeObjectOfClass:[NSData class] forKey:@"plaintextData"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.plaintextData.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    OWSStaticOutgoingMessage *typedOther = (OWSStaticOutgoingMessage *)other;
    if (![NSObject isObject:self.plaintextData equalToObject:typedOther.plaintextData]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSStaticOutgoingMessage *result = [super copyWithZone:zone];
    result->_plaintextData = self.plaintextData;
    return result;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (nullable NSData *)buildPlainTextData:(TSThread *)thread transaction:(DBWriteTransaction *)transaction
{
    return self.plaintextData;
}

@end

NS_ASSUME_NONNULL_END
