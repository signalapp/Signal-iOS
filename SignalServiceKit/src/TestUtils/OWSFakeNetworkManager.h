//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSNetworkManager.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@interface OWSFakeNetworkManager : TSNetworkManager

- (instancetype)init;

@end

#endif

NS_ASSUME_NONNULL_END
