//
//  NSData+messagePadding.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "NSData+messagePadding.h"

@implementation NSData (messagePadding)

- (NSData*)removePadding{
    unsigned long paddingStart = self.length;
    
    Byte data[self.length];
    [self getBytes:data length:self.length];
    
    
    for (long i = (long)self.length-1; i >= 0; i--) {
        if (data[i] == (Byte)0x80) {
            paddingStart = (unsigned long) i;
            break;
        } else if (data[i] != (Byte)0x00) {
            return self;
        }
    }
    
    return [self subdataWithRange:NSMakeRange(0, paddingStart)];
}

@end
