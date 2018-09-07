//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SSKEnvironment.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSUnitTestEnvironment : SSKEnvironment

+ (void)ensureSetup;
- (instancetype)initDefault;

@end

NS_ASSUME_NONNULL_END
