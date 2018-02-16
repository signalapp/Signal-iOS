//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NSString+OWS.h"
#import "UIView+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSString (OWS)

- (NSString *)rtlSafeAppend:(NSString *)string referenceView:(UIView *)referenceView
{
    OWSAssert(string);
    OWSAssert(referenceView);

    if ([referenceView isRTL]) {
        return [string stringByAppendingString:self];
    } else {
        return [self stringByAppendingString:string];
    }
}

@end

NS_ASSUME_NONNULL_END
