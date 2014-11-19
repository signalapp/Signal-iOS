//
//  NSString+escape.m
//  TextSecureiOS
//
//  Created by Frederic Jacobs on 9/29/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "NSString+escape.h"

@implementation NSString (escape)

- (NSString*) escape{
    return [self stringByAddingPercentEscapesUsingEncoding:
     NSASCIIStringEncoding];
}

@end
