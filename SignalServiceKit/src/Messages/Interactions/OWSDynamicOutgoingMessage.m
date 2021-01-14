//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

- (instancetype)initWithThread:(TSThread *)thread plainTextDataBlock:(DynamicOutgoingMessageBlock)block
{
    return [self initWithThread:thread timestamp:[NSDate ows_millisecondTimeStamp] plainTextDataBlock:block];
}

// MJK TODO can we remove sender timestamp?
- (instancetype)initWithThread:(TSThread *)thread
                     timestamp:(uint64_t)timestamp
            plainTextDataBlock:(DynamicOutgoingMessageBlock)block
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    messageBuilder.timestamp = timestamp;
    self = [super initOutgoingMessageWithBuilder:messageBuilder];

    if (self) {
        _block = block;
    }

    return self;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (nullable NSData *)buildPlainTextData:(SignalServiceAddress *)address
                                 thread:(TSThread *)thread
                            transaction:(SDSAnyReadTransaction *)transaction
{
    NSData *plainTextData = self.block(address);
    OWSAssertDebug(plainTextData);
    return plainTextData;
}

@end

NS_ASSUME_NONNULL_END
