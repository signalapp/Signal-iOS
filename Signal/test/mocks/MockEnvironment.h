//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/Environment.h>

NS_ASSUME_NONNULL_BEGIN

@interface MockEnvironment : Environment

+ (MockEnvironment *)activate;

- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
