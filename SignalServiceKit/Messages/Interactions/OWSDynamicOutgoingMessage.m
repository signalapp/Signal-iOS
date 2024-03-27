//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSDynamicOutgoingMessage.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSDynamicOutgoingMessage ()

@property (nonatomic, readonly) DynamicOutgoingMessageBlock block;

@end

#pragma mark -

@implementation OWSDynamicOutgoingMessage

- (instancetype)initWithThread:(TSThread *)thread
                   transaction:(SDSAnyReadTransaction *)transaction
            plainTextDataBlock:(DynamicOutgoingMessageBlock)block
{
    return [self initWithThread:thread
                      timestamp:[NSDate ows_millisecondTimeStamp]
                    transaction:transaction
             plainTextDataBlock:block];
}

// MJK TODO can we remove sender timestamp?
- (instancetype)initWithThread:(TSThread *)thread
                     timestamp:(uint64_t)timestamp
                   transaction:(SDSAnyReadTransaction *)transaction
            plainTextDataBlock:(DynamicOutgoingMessageBlock)block
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    messageBuilder.timestamp = timestamp;
    self = [super initOutgoingMessageWithBuilder:messageBuilder transaction:transaction];

    if (self) {
        _block = block;
    }

    return self;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (nullable NSData *)buildPlainTextData:(TSThread *)thread transaction:(SDSAnyWriteTransaction *)transaction
{
    NSData *plainTextData = self.block();
    OWSAssertDebug(plainTextData);
    return plainTextData;
}

@end

NS_ASSUME_NONNULL_END
