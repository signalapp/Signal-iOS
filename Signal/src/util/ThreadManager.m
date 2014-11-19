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

static ThreadManager* sharedInstance = nil;

+ (instancetype)sharedInstance {
    static ThreadManager* sharedInstance = nil;
    static dispatch_once_t onceToken = 0;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[ThreadManager alloc] init];
        sharedInstance.low = [[RunningThreadRunLoopPair alloc] initWithThreadName:LOW_THREAD_NAME];
        sharedInstance.normal = [[RunningThreadRunLoopPair alloc] initWithThreadName:NORMAL_THREAD_NAME];
        sharedInstance.high = [[RunningThreadRunLoopPair alloc] initWithThreadName:HIGH_THREAD_NAME];
    });
    return sharedInstance;
}

+ (NSThread*)lowLatencyThread {
    return [ThreadManager sharedInstance].low.thread;
}

+ (NSRunLoop*)lowLatencyThreadRunLoop {
    return [ThreadManager sharedInstance].low.runLoop;
}

+ (NSThread*)normalLatencyThread {
    return [ThreadManager sharedInstance].normal.thread;
}

+ (NSRunLoop*)normalLatencyThreadRunLoop {
    return [ThreadManager sharedInstance].normal.runLoop;
}

+ (NSThread*)highLatencyThread {
    return [ThreadManager sharedInstance].high.thread;
}

+ (NSRunLoop*)highLatencyThreadRunLoop {
    return [ThreadManager sharedInstance].high.runLoop;
}

+ (void)terminate {
    @synchronized(self) {
        if (sharedInstance == nil) return;
        [sharedInstance.low terminate];
        [sharedInstance.normal terminate];
        [sharedInstance.high terminate];
        sharedInstance = nil;
    }
}

@end
