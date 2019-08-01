//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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
    // MJK TODO - remove sender timestamp
    self = [super initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                          inThread:thread
                                       messageBody:nil
                                     attachmentIds:[NSMutableArray new]
                                  expiresInSeconds:0
                                   expireStartedAt:0
                                    isVoiceMessage:NO
                                  groupMetaMessage:TSGroupMetaMessageUnspecified
                                     quotedMessage:nil
                                      contactShare:nil
                                       linkPreview:nil
                                    messageSticker:nil
                                 isViewOnceMessage:NO];
    if (!self) {
        return self;
    }

    _configuration = configuration;

    return self;
}


- (nullable SSKProtoDataMessageBuilder *)dataMessageBuilder
{
    SSKProtoDataMessageBuilder *_Nullable dataMessageBuilder = [super dataMessageBuilder];
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
