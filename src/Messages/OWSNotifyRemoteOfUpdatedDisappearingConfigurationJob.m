//  Created by Michael Kirk on 9/25/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSNotifyRemoteOfUpdatedDisappearingConfigurationJob.h"
#import "OWSDisappearingMessagesConfigurationMessage.h"
#import "OWSMessageSender.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSNotifyRemoteOfUpdatedDisappearingConfigurationJob ()

@property (nonatomic, readonly) OWSDisappearingMessagesConfiguration *configuration;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) TSThread *thread;

@end

@implementation OWSNotifyRemoteOfUpdatedDisappearingConfigurationJob

- (instancetype)initWithConfiguration:(OWSDisappearingMessagesConfiguration *)configuration
                               thread:(TSThread *)thread
                        messageSender:(OWSMessageSender *)messageSender
{
    self = [super init];
    if (!self) {
        return self;
    }

    _thread = thread;
    _configuration = configuration;
    _messageSender = messageSender;

    return self;
}

+ (void)runWithConfiguration:(OWSDisappearingMessagesConfiguration *)configuration
                      thread:(TSThread *)thread
               messageSender:(OWSMessageSender *)messageSender
{
    OWSNotifyRemoteOfUpdatedDisappearingConfigurationJob *job =
        [[self alloc] initWithConfiguration:configuration thread:thread messageSender:messageSender];
    [job run];
}

- (void)run
{
    OWSDisappearingMessagesConfigurationMessage *message =
        [[OWSDisappearingMessagesConfigurationMessage alloc] initWithConfiguration:self.configuration
                                                                            thread:self.thread];

    [self.messageSender sendMessage:message
        success:^{
            DDLogDebug(
                @"%@ Successfully notified %@ of new disappearing messages configuration", self.tag, self.thread);
        }
        failure:^(NSError *error) {
            DDLogError(@"%@ Failed to notify %@ of new disappearing messages configuration with error: %@",
                self.tag,
                self.thread,
                error);
        }];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
