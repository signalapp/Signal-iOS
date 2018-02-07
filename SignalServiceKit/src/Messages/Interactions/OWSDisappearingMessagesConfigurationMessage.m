//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDisappearingMessagesConfigurationMessage.h"
#import "NSDate+OWS.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSSignalServiceProtos.pb.h"

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
    self = [super initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                          inThread:thread
                                       messageBody:nil
                                     attachmentIds:[NSMutableArray new]
                                  expiresInSeconds:0
                                   expireStartedAt:0
                                    isVoiceMessage:NO
                                  groupMetaMessage:TSGroupMessageNone
                                     quotedMessage:nil];
    if (!self) {
        return self;
    }

    _configuration = configuration;

    return self;
}


- (OWSSignalServiceProtosDataMessageBuilder *)dataMessageBuilder
{
    OWSSignalServiceProtosDataMessageBuilder *dataMessageBuilder = [super dataMessageBuilder];
    [dataMessageBuilder setTimestamp:self.timestamp];
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
