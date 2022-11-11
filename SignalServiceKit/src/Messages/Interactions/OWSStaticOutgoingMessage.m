//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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

- (instancetype)initWithThread:(TSThread *)thread
                 plaintextData:(NSData *)plaintextData
                   transaction:(SDSAnyReadTransaction *)transaction
{
    return [self initWithThread:thread
                      timestamp:[NSDate ows_millisecondTimeStamp]
                  plaintextData:plaintextData
                    transaction:transaction];
}

- (instancetype)initWithThread:(TSThread *)thread
                     timestamp:(uint64_t)timestamp
                 plaintextData:(NSData *)plaintextData
                   transaction:(SDSAnyReadTransaction *)transaction
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    messageBuilder.timestamp = timestamp;
    self = [super initOutgoingMessageWithBuilder:messageBuilder transaction:transaction];

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
