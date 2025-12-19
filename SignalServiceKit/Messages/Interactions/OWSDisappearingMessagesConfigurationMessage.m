//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSDisappearingMessagesConfigurationMessage.h"
#import "OWSDisappearingMessagesConfiguration.h"
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

- (BOOL)isUrgent
{
    return NO;
}

- (instancetype)initWithConfiguration:(OWSDisappearingMessagesConfiguration *)configuration
                               thread:(TSThread *)thread
                          transaction:(DBReadTransaction *)transaction
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder
                            additionalRecipients:@[]
                              explicitRecipients:@[]
                               skippedRecipients:@[]
                                     transaction:transaction];
    if (!self) {
        return self;
    }

    _configuration = configuration;

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    OWSDisappearingMessagesConfiguration *configuration = self.configuration;
    if (configuration != nil) {
        [coder encodeObject:configuration forKey:@"configuration"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_configuration = [coder decodeObjectOfClass:[OWSDisappearingMessagesConfiguration class]
                                               forKey:@"configuration"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.configuration.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    OWSDisappearingMessagesConfigurationMessage *typedOther = (OWSDisappearingMessagesConfigurationMessage *)other;
    if (![NSObject isObject:self.configuration equalToObject:typedOther.configuration]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSDisappearingMessagesConfigurationMessage *result = [super copyWithZone:zone];
    result->_configuration = self.configuration;
    return result;
}


- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilderWithThread:(TSThread *)thread
                                                          transaction:(DBReadTransaction *)transaction
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
    [dataMessageBuilder setExpireTimerVersion:self.configuration.timerVersion];

    return dataMessageBuilder;
}

@end

NS_ASSUME_NONNULL_END
