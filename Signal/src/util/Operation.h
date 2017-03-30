//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "StringUtil.h"

typedef void (^Action)(void);
typedef id (^Function)(void);

@interface Operation : NSObject

@property (nonatomic, readonly, copy) Action callback;

+ (Operation *)operation:(Action)block;

+ (void)asyncRun:(Action)action onThread:(NSThread *)thread;

+ (void)asyncRunAndWaitUntilDone:(Action)action onThread:(NSThread *)thread;

+ (void)asyncRunOnNewThread:(Action)action;

- (void)run;

- (SEL)selectorToRun;

- (void)performOnNewThread;

- (void)performOnThread:(NSThread *)thread;

- (void)performOnThreadAndWaitUntilDone:(NSThread *)thread;

@end
