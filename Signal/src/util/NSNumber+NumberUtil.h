//
//  NSNumber+NumberUtil.h
//  Signal
//
//  Created by Gil Azaria on 3/11/2014.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSNumber (NumberUtil)

- (bool)hasUnsignedIntegerValue;
- (bool)hasUnsignedLongLongValue;
- (bool)hasLongLongValue;

@end
