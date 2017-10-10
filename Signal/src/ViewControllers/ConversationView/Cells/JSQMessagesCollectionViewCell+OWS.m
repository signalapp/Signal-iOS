//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "JSQMessagesCollectionViewCell+OWS.h"
#import "UIColor+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@implementation JSQMessagesCollectionViewCell (OWS)

- (UIColor *)ows_textColor
{
    return [UIColor ows_blackColor];
}

- (void)ows_didLoad
{
    self.textView.textColor = self.ows_textColor;
    self.textView.linkTextAttributes = @{
        NSForegroundColorAttributeName : self.ows_textColor,
        NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle | NSUnderlinePatternSolid)
    };

    self.textView.dataDetectorTypes
        = (UIDataDetectorTypeLink | UIDataDetectorTypeAddress | UIDataDetectorTypeCalendarEvent);
}

@end

NS_ASSUME_NONNULL_END
