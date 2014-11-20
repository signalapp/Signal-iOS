#import "Util.h"
#import "Constraints.h"

@interface Operation ()

@property (nonatomic, readwrite, copy) Action callback;

@end

@implementation Operation

- (instancetype)initWithAction:(Action)block {
    self = [super init];
	
    if (self) {
        require(block != NULL);
        self.callback = block;
    }
    
    return self;
}

+ (void)asyncRun:(Action)action
        onThread:(NSThread*)thread {
    
    require(action != nil);
    require(thread != nil);
    
    [[[Operation alloc] initWithAction:action] performOnThread:thread];
}

+ (void)asyncRunAndWaitUntilDone:(Action)action
                        onThread:(NSThread*)thread {
    
    require(action != nil);
    require(thread != nil);
    
    [[[Operation alloc] initWithAction:action] performOnThreadAndWaitUntilDone:thread];
}

+ (void)asyncRunOnNewThread:(Action)action {
    require(action != nil);
    [[[Operation alloc] initWithAction:action] performOnNewThread];
}

- (SEL)selectorToRun {
    return @selector(run);
}

- (void)performOnThread:(NSThread*)thread {
    require(thread != nil);
    [self performSelector:@selector(run) onThread:thread withObject:nil waitUntilDone:thread == NSThread.currentThread];
}

- (void)performOnThreadAndWaitUntilDone:(NSThread*)thread {
    require(thread != nil);
    [self performSelector:@selector(run) onThread:thread withObject:nil waitUntilDone:true];
}

- (void)performOnNewThread {
    [NSThread detachNewThreadSelector:[self selectorToRun] toTarget:self withObject:nil];
}

- (void)run {
    self.callback();
}

@end
