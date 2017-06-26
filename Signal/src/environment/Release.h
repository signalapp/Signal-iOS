//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Environment.h"

@interface Release : NSObject

/// Connects to actual production infrastructure
+ (Environment *)releaseEnvironment;

+ (Environment *)stagingEnvironment;

/// Fake environment with no logging
+ (Environment *)unitTestEnvironment:(NSArray *)testingAndLegacyOptions;

@end
