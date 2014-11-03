#import "ThreadManager.h"
#import "Util.h"

#define LOW_THREAD_NAME @"Audio Thread"
#define NORMAL_THREAD_NAME @"Background Thread"
#define HIGH_THREAD_NAME @"Blocking Working Thread"

@interface ThreadManager ()

@property (strong, nonatomic) RunningThreadRunLoopPair* low;
@property (strong, nonatomic) RunningThreadRunLoopPair* normal;
@property (strong, nonatomic) RunningThreadRunLoopPair* high;

@end

@implementation ThreadManager

static ThreadManager* sharedThreadManagerInternal;

+ (ThreadManager*)sharedThreadManager {
    @synchronized(self) {
        if (sharedThreadManagerInternal == nil) {
            sharedThreadManagerInternal = [[ThreadManager alloc] init];
            sharedThreadManagerInternal.low = [[RunningThreadRunLoopPair alloc] initWithThreadName:LOW_THREAD_NAME];
            sharedThreadManagerInternal.normal = [[RunningThreadRunLoopPair alloc] initWithThreadName:NORMAL_THREAD_NAME];
            sharedThreadManagerInternal.high = [[RunningThreadRunLoopPair alloc] initWithThreadName:HIGH_THREAD_NAME];
        }
    }
    
    return sharedThreadManagerInternal;
}

+ (NSThread*)lowLatencyThread {
    return [self sharedThreadManager].low.thread;
}

+ (NSRunLoop*)lowLatencyThreadRunLoop {
    return [self sharedThreadManager].low.runLoop;
}

+ (NSThread*)normalLatencyThread {
    return [self sharedThreadManager].normal.thread;
}

+ (NSRunLoop*)normalLatencyThreadRunLoop {
    return [self sharedThreadManager].normal.runLoop;
}

+ (NSThread*)highLatencyThread {
    return [self sharedThreadManager].high.thread;
}

+ (NSRunLoop*)highLatencyThreadRunLoop {
    return [self sharedThreadManager].high.runLoop;
}

+ (void)terminate {
    @synchronized(self) {
        if (sharedThreadManagerInternal == nil) return;
        [sharedThreadManagerInternal.low terminate];
        [sharedThreadManagerInternal.normal terminate];
        [sharedThreadManagerInternal.high terminate];
        sharedThreadManagerInternal = nil;
    }
}

@end
