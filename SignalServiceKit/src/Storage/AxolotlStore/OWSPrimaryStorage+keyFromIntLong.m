//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSPrimaryStorage+keyFromIntLong.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSPrimaryStorage (keyFromIntLong)

- (NSString *)keyFromInt:(int)integer
{
    return [[NSNumber numberWithInteger:integer] stringValue];
}

@end

NS_ASSUME_NONNULL_END
