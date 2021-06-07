//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSNetworkManager.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@interface OWSFakeNetworkManager : TSNetworkManager

- (instancetype)init NS_DESIGNATED_INITIALIZER;

@end

#endif

NS_ASSUME_NONNULL_END
