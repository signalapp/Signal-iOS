#import "ThreadManager.h"
#import "Util.h"

#define LOW_THREAD_NAME @"Audio Thread"
#define NORMAL_THREAD_NAME @"Background Thread"
#define HIGH_THREAD_NAME @"Blocking Working Thread"

@implementation RunningThreadRunLoopPair

@synthesize runLoop, thread;

+ (RunningThreadRunLoopPair *)startNewWithThreadName:(NSString *)name {
    ows_require(name != nil);

    RunningThreadRunLoopPair *instance = [RunningThreadRunLoopPair new];
    instance->thread = [[NSThread alloc] initWithTarget:instance selector:@selector(runLoopUntilCancelled) object:nil];
    [instance->thread setName:name];
    [instance->thread start];

    [Operation asyncRunAndWaitUntilDone:^{
      instance->runLoop = NSRunLoop.currentRunLoop;
    }
                               onThread:instance->thread];

    return instance;
}
- (void)terminate {
    [thread cancel];
}
- (void)runLoopUntilCancelled {
    NSThread *curThread   = NSThread.currentThread;
    NSRunLoop *curRunLoop = NSRunLoop.currentRunLoop;
    while (!curThread.isCancelled) {
        [curRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:5]];
    }
}

@end

@implementation ThreadManager

static ThreadManager *sharedThreadManagerInternal;

+ (ThreadManager *)sharedThreadManager {
    @synchronized(self) {
        if (sharedThreadManagerInternal == nil) {
            sharedThreadManagerInternal         = [ThreadManager new];
            sharedThreadManagerInternal->low    = [RunningThreadRunLoopPair startNewWithThreadName:LOW_THREAD_NAME];
            sharedThreadManagerInternal->normal = [RunningThreadRunLoopPair startNewWithThreadName:NORMAL_THREAD_NAME];
            sharedThreadManagerInternal->high   = [RunningThreadRunLoopPair startNewWithThreadName:HIGH_THREAD_NAME];
        }
    }
    return sharedThreadManagerInternal;
}

+ (NSThread *)lowLatencyThread {
    return self.sharedThreadManager->low.thread;
}
+ (NSRunLoop *)lowLatencyThreadRunLoop {
    return self.sharedThreadManager->low.runLoop;
}

+ (NSThread *)normalLatencyThread {
    return self.sharedThreadManager->normal.thread;
}
+ (NSRunLoop *)normalLatencyThreadRunLoop {
    return self.sharedThreadManager->normal.runLoop;
}

+ (NSThread *)highLatencyThread {
    return self.sharedThreadManager->high.thread;
}
+ (NSRunLoop *)highLatencyThreadRunLoop {
    return self.sharedThreadManager->high.runLoop;
}

+ (void)terminate {
    @synchronized(self) {
        if (sharedThreadManagerInternal == nil)
            return;
        [sharedThreadManagerInternal->low terminate];
        [sharedThreadManagerInternal->normal terminate];
        [sharedThreadManagerInternal->high terminate];
        sharedThreadManagerInternal = nil;
    }
}

@end
