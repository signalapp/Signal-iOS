//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NSAttributedString+OWS.h"
#import "UIView+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSAttributedString (OWS)

- (NSAttributedString *)rtlSafeAppend:(NSAttributedString *)string referenceView:(UIView *)referenceView
{
    OWSAssert(string);
    OWSAssert(referenceView);

    NSMutableAttributedString *result = [NSMutableAttributedString new];
    if ([referenceView isRTL]) {
        [result appendAttributedString:string];
        [result appendAttributedString:self];
    } else {
        [result appendAttributedString:self];
        [result appendAttributedString:string];
    }
    return [result copy];
}

@end

NS_ASSUME_NONNULL_END
