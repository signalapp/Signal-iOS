//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSInfoMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSDisappearingMessagesConfiguration;
@class TSThread;

@interface OWSDisappearingConfigurationUpdateInfoMessage : TSInfoMessage

@property (nonatomic, readonly) BOOL configurationIsEnabled;

/**
 * @param remoteName is nil when created by the local user
 */
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                    configuration:(OWSDisappearingMessagesConfiguration *)configuration
              createdByRemoteName:(nullable NSString *)remoteName
           createdInExistingGroup:(BOOL)createdInExistingGroup;

@end

NS_ASSUME_NONNULL_END
