//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSPrimaryStorage+keyFromIntLong.h"

@implementation OWSPrimaryStorage (keyFromIntLong)

- (NSString *)keyFromInt:(int)integer
{
    return [[NSNumber numberWithInteger:integer] stringValue];
}

@end
