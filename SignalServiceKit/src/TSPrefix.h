//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@import CocoaLumberjack;

//#ifdef DEBUG
static const NSUInteger ddLogLevel = DDLogLevelAll;
//#else
// static const NSUInteger ddLogLevel = DDLogLevelInfo;
//#endif
#import "Constraints.h"
#import "NSObject+OWS.h"
#import "OWSAnalytics.h"
#import "OWSAsserts.h"
#import "OWSDispatch.h"
#import "iOSVersions.h"

#define BLOCK_SAFE_RUN(block, ...)                                                        \
    block ? dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), \
                           ^{                                                             \
                             block(__VA_ARGS__);                                          \
                           })                                                             \
          : nil
#define SYNC_BLOCK_SAFE_RUN(block, ...) block ? block(__VA_ARGS__) : nil

#define MacrosSingletonImplemention          \
    +(instancetype)sharedInstance {          \
        static dispatch_once_t onceToken;    \
        static id sharedInstance = nil;      \
        dispatch_once(&onceToken, ^{         \
          sharedInstance = [self.class new]; \
        });                                  \
                                             \
        return sharedInstance;               \
    }

#define MacrosSingletonInterface +(instancetype)sharedInstance;
