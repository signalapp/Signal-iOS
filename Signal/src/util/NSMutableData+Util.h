//
//  NSMutableData+Util.h
//  Signal
//
//  Created by Gil Azaria on 3/11/2014.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSMutableData (Util)

- (void)replaceBytesStartingAt:(NSUInteger)offset
                      withData:(NSData*)data;

- (void)setUint8At:(NSUInteger)offset
                to:(uint8_t)newValue;

@end
