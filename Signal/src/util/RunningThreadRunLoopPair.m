//
//  RunningThreadRunLoopPair.m
//  Signal
//
//  Created by Gil Azaria on 3/11/2014.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "RunningThreadRunLoopPair.h"
#import "Util.h"

@interface RunningThreadRunLoopPair ()

@property (nonatomic, readwrite) NSThread* thread;
@property (nonatomic, readwrite) NSRunLoop* runLoop;

@end

@implementation RunningThreadRunLoopPair

- (instancetype)initWithThreadName:(NSString*)name {
    if (self = [super init]) {
        require(name != nil);
        self.thread = [[NSThread alloc] initWithTarget:self selector:@selector(runLoopUntilCancelled) object:nil];
        [self.thread setName:name];
        [self.thread start];
        
        [Operation asyncRunAndWaitUntilDone:^{
            self.runLoop = [NSRunLoop currentRunLoop];
        } onThread:self.thread];
    }
    
    return self;
}

- (void)terminate {
    [self.thread cancel];
}

- (void)runLoopUntilCancelled {
    NSThread* curThread = NSThread.currentThread;
    NSRunLoop* curRunLoop = [NSRunLoop currentRunLoop];
    
    while (!curThread.isCancelled) {
        [curRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:5]];
    }
}

@end
