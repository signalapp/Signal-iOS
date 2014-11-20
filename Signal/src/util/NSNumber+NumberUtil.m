//
//  NSNumber+NumberUtil.m
//  Signal
//
//  Created by Gil Azaria on 3/11/2014.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "NSNumber+NumberUtil.h"

@implementation NSNumber (NumberUtil)

- (bool)hasUnsignedIntegerValue {
    return [self isEqual:@([self unsignedIntegerValue])];
}

- (bool)hasUnsignedLongLongValue {
    return [self isEqual:@([self unsignedLongLongValue])];
}

- (bool)hasLongLongValue {
    return [self isEqual:@([self longLongValue])];
}

@end
