//  Created by Michael Kirk on 9/25/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "TSInfoMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class TSThread;
@class OWSDisappearingMessagesConfiguration;

@interface OWSDisappearingConfigurationUpdateInfoMessage : TSInfoMessage

/**
 * When remote user updates configuration
 */
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                    configuration:(OWSDisappearingMessagesConfiguration *)configuration
              createdByRemoteName:(NSString *)name;

/**
 * When local user updates configuration
 */
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                    configuration:(OWSDisappearingMessagesConfiguration *)configuration;

@end

NS_ASSUME_NONNULL_END
