//
//  NSMutableData+Util.m
//  Signal
//
//  Created by Gil Azaria on 3/11/2014.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "NSMutableData+Util.h"
#import "NSData+Util.h"
#import "Constraints.h"

@implementation NSMutableData (Util)

- (void)setUint8At:(NSUInteger)offset
                to:(uint8_t)newValue {
    require(offset < self.length);
    ((uint8_t*)[self mutableBytes])[offset] = newValue;
}

- (void)replaceBytesStartingAt:(NSUInteger)offset
                      withData:(NSData*)data {
    require(data != nil);
    require(offset + data.length <= self.length);
    [self replaceBytesInRange:NSMakeRange(offset, data.length) withBytes:[data bytes]];
}

@end
