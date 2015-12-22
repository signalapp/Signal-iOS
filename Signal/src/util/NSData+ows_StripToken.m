//
//  NSData+ows_StripToken.m
//  Signal
//
//  Created by Frederic Jacobs on 14/04/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "NSData+ows_StripToken.h"

@implementation NSData (ows_StripToken)

- (NSString *)ows_tripToken {
    return [[[NSString stringWithFormat:@"%@", self]
        stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]]
        stringByReplacingOccurrencesOfString:@" "
                                  withString:@""];
}

@end
