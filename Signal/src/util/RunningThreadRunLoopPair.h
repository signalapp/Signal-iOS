//
//  RunningThreadRunLoopPair.h
//  Signal
//
//  Created by Gil Azaria on 3/11/2014.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RunningThreadRunLoopPair : NSObject

@property (nonatomic, readonly) NSThread* thread;
@property (nonatomic, readonly) NSRunLoop* runLoop;

- (instancetype)initWithThreadName:(NSString*)name;
- (void)terminate;

@end
