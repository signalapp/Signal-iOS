//  Created by Michael Kirk on 9/25/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class OWSDisappearingMessagesConfiguration;
@class OWSMessageSender;
@class TSThread;

@interface OWSNotifyRemoteOfUpdatedDisappearingConfigurationJob : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithConfiguration:(OWSDisappearingMessagesConfiguration *)configuration
                               thread:(TSThread *)thread
                        messageSender:(OWSMessageSender *)messageSender NS_DESIGNATED_INITIALIZER;

+ (void)runWithConfiguration:(OWSDisappearingMessagesConfiguration *)configuration
                      thread:(TSThread *)thread
               messageSender:(OWSMessageSender *)messageSender;

- (void)run;

@end

NS_ASSUME_NONNULL_END
