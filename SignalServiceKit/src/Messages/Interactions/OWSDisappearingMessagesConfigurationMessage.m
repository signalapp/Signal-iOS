//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSDisappearingMessagesConfigurationMessage.h"
#import "NSDate+OWS.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSDisappearingMessagesConfigurationMessage ()

@property (nonatomic, readonly) OWSDisappearingMessagesConfiguration *configuration;

@end

@implementation OWSDisappearingMessagesConfigurationMessage

- (BOOL)shouldBeSaved
{
    return NO;
}

- (instancetype)initWithConfiguration:(OWSDisappearingMessagesConfiguration *)configuration thread:(TSThread *)thread
{
    self = [super initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:thread];
    if (!self) {
        return self;
    }

    _configuration = configuration;

    return self;
}


- (OWSSignalServiceProtosDataMessageBuilder *)dataMessageBuilder
{
    OWSSignalServiceProtosDataMessageBuilder *dataMessageBuilder = [super dataMessageBuilder];
    [dataMessageBuilder setFlags:OWSSignalServiceProtosDataMessageFlagsExpirationTimerUpdate];
    if (self.configuration.isEnabled) {
        [dataMessageBuilder setExpireTimer:self.configuration.durationSeconds];
    } else {
        [dataMessageBuilder setExpireTimer:0];
    }

    return dataMessageBuilder;
}

@end

NS_ASSUME_NONNULL_END
