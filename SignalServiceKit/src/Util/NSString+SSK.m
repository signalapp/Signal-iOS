//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NSString+SSK.h"
#import "AppContext.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSString (SSK)

- (NSString *)rtlSafeAppend:(NSString *)string
{
    OWSAssertDebug(string);

    if (CurrentAppContext().isRTL) {
        return [string stringByAppendingString:self];
    } else {
        return [self stringByAppendingString:string];
    }
}

@end

NS_ASSUME_NONNULL_END
