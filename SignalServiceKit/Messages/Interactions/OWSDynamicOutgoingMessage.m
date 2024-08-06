//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSDynamicOutgoingMessage.h"
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@interface OWSDynamicOutgoingMessage ()

@property (nonatomic, readonly) DynamicOutgoingMessageBlock block;

@end

#pragma mark -

@implementation OWSDynamicOutgoingMessage

- (instancetype)initWithThread:(TSThread *)thread
                   transaction:(SDSAnyReadTransaction *)transaction
            plainTextDataBlock:(DynamicOutgoingMessageBlock)block
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder
                            additionalRecipients:@[]
                              explicitRecipients:@[]
                               skippedRecipients:@[]
                                     transaction:transaction];

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

#endif

NS_ASSUME_NONNULL_END
