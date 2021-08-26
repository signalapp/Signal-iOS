//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSStaticOutgoingMessage.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSStaticOutgoingMessage ()

@property (nonatomic, readonly) NSData *plaintextData;

@end

#pragma mark -

@implementation OWSStaticOutgoingMessage

- (instancetype)initWithThread:(TSThread *)thread plaintextData:(NSData *)plaintextData
{
    return [self initWithThread:thread timestamp:[NSDate ows_millisecondTimeStamp] plaintextData:plaintextData];
}

- (instancetype)initWithThread:(TSThread *)thread timestamp:(uint64_t)timestamp plaintextData:(NSData *)plaintextData
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    messageBuilder.timestamp = timestamp;
    self = [super initOutgoingMessageWithBuilder:messageBuilder];

    if (self) {
        _plaintextData = plaintextData;
    }

    return self;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (nullable NSData *)buildPlainTextData:(TSThread *)thread transaction:(SDSAnyWriteTransaction *)transaction
{
    return self.plaintextData;
}

@end

NS_ASSUME_NONNULL_END
