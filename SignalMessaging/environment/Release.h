//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@class Environment;

@interface Release : NSObject

/// Connects to actual production infrastructure
+ (Environment *)releaseEnvironment;

@end
