//  Created by Michael Kirk on 9/25/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSNotifyRemoteOfUpdatedDisappearingConfigurationJob.h"
#import "OWSDisappearingMessagesConfigurationMessage.h"
#import "TSMessagesManager+sendMessages.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSNotifyRemoteOfUpdatedDisappearingConfigurationJob ()

@property (nonatomic, readonly) OWSDisappearingMessagesConfiguration *configuration;
@property (nonatomic, readonly) TSMessagesManager *messageManager;
@property (nonatomic, readonly) TSThread *thread;

@end

@implementation OWSNotifyRemoteOfUpdatedDisappearingConfigurationJob

- (instancetype)initWithConfiguration:(OWSDisappearingMessagesConfiguration *)configuration
                               thread:(TSThread *)thread
                      messagesManager:(TSMessagesManager *)messagesManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _thread = thread;
    _configuration = configuration;
    _messageManager = messagesManager;

    return self;
}

+ (void)runWithConfiguration:(OWSDisappearingMessagesConfiguration *)configuration
                      thread:(TSThread *)thread
             messagesManager:(TSMessagesManager *)messagesManager
{
    OWSNotifyRemoteOfUpdatedDisappearingConfigurationJob *job =
        [[self alloc] initWithConfiguration:configuration thread:thread messagesManager:messagesManager];
    [job run];
}

- (void)run
{
    OWSDisappearingMessagesConfigurationMessage *message =
        [[OWSDisappearingMessagesConfigurationMessage alloc] initWithConfiguration:self.configuration
                                                                            thread:self.thread];

    [self.messageManager sendMessage:message
        inThread:self.thread
        success:^{
            DDLogDebug(
                @"%@ Successfully notified %@ of new disappearing messages configuration", self.tag, self.thread);
        }
        failure:^{
            DDLogError(@"%@ Failed to notify %@ of new disappearing messages configuration", self.tag, self.thread);
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
