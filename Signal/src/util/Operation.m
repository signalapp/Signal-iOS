#import "Util.h"
#import "Constraints.h"
#import "FutureSource.h"

@implementation Operation

+(Operation*) operation:(Action)block {
    require(block != NULL);
    Operation* a = [Operation new];
    a->_callback = block;
    return a;
}

+(void) asyncRun:(Action)action
        onThread:(NSThread*)thread {
    
    require(action != nil);
    require(thread != nil);
    
    [[Operation operation:action] performOnThread:thread];
}

+(Future*) asyncEvaluate:(Function)function
                   onThread:(NSThread*)thread {
    
    require(function != nil);
    require(thread != nil);
    
    FutureSource* result = [FutureSource new];
    Action evaler = ^() {
        [result trySetResult:function()];
    };
    [[Operation operation:evaler] performOnThread:thread];
    return result;
}

+(void) asyncRunAndWaitUntilDone:(Action)action
                        onThread:(NSThread*)thread {
    
    require(action != nil);
    require(thread != nil);
    
    [[Operation operation:action] performOnThreadAndWaitUntilDone:thread];
}

+(void) asyncRunOnNewThread:(Action)action {
    require(action != nil);
    [[Operation operation:action] performOnNewThread];
}

+(Future*) asyncEvaluateOnNewThread:(Function)function {
    
    require(function != nil);
    
    FutureSource* result = [FutureSource new];
    Action evaler = ^() {
        [result trySetResult:function()];
    };
    [[Operation operation:evaler] performOnNewThread];
    return result;
}

-(SEL) selectorToRun {
    return @selector(run);
}

-(void) performOnThread:(NSThread*)thread {
    require(thread != nil);
    [self performSelector:@selector(run) onThread:thread withObject:nil waitUntilDone:thread == [NSThread currentThread]];
}

-(void) performOnThreadAndWaitUntilDone:(NSThread*)thread {
    require(thread != nil);
    [self performSelector:@selector(run) onThread:thread withObject:nil waitUntilDone:true];
}

-(void) performOnNewThread {
    [NSThread detachNewThreadSelector:[self selectorToRun] toTarget:self withObject:nil];
}

-(void) run {
    _callback();
}

@end
