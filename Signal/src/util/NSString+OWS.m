//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NSString+OWS.h"

@implementation NSString (OWS)

- (NSString *)ows_stripped
{
    return [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

@end
