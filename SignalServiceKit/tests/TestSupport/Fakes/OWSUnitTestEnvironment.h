//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TextSecureKitEnv.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSUnitTestEnvironment : TextSecureKitEnv

+ (void)ensureSetup;
- (instancetype)initDefault;

@end

NS_ASSUME_NONNULL_END
