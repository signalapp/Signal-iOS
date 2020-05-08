//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSDisappearingMessagesConfigurationMessage.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSDisappearingMessagesConfigurationMessage ()

@property (nonatomic, readonly) OWSDisappearingMessagesConfiguration *configuration;

@end

#pragma mark -

@implementation OWSDisappearingMessagesConfigurationMessage

- (BOOL)shouldBeSaved
{
    return NO;
}

- (instancetype)initWithConfiguration:(OWSDisappearingMessagesConfiguration *)configuration thread:(TSThread *)thread
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder];
    if (!self) {
        return self;
    }

    _configuration = configuration;

    return self;
}


- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilderWithThread:(TSThread *)thread
                                                          transaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoDataMessageBuilder *_Nullable dataMessageBuilder = [super dataMessageBuilderWithThread:thread
                                                                                       transaction:transaction];
    if (!dataMessageBuilder) {
        return nil;
    }
    [dataMessageBuilder setTimestamp:self.timestamp];
    [dataMessageBuilder setFlags:SSKProtoDataMessageFlagsExpirationTimerUpdate];
    if (self.configuration.isEnabled) {
        [dataMessageBuilder setExpireTimer:self.configuration.durationSeconds];
    } else {
        [dataMessageBuilder setExpireTimer:0];
    }

    return dataMessageBuilder;
}

@end

NS_ASSUME_NONNULL_END
