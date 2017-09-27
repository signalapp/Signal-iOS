//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NSString+OWS.h"
#import "UIView+OWS.h"

@implementation NSString (OWS)

- (NSString *)ows_stripped
{
    return [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

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
