//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSStaticOutgoingMessage.h"
#import <SignalServiceKit/NSDate+OWS.h>
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
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
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
