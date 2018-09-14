//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSNetworkManager.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG

@interface OWSFakeNetworkManager : TSNetworkManager

- (instancetype)init;

@end

#endif

NS_ASSUME_NONNULL_END
