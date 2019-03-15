//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSTextView.h"
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

const UIDataDetectorTypes kOWSAllowedDataDetectorTypes
    = UIDataDetectorTypeLink | UIDataDetectorTypeAddress | UIDataDetectorTypeCalendarEvent;

const UIDataDetectorTypes kOWSAllowedDataDetectorTypesExceptLinks
    = UIDataDetectorTypeAddress | UIDataDetectorTypeCalendarEvent;

@implementation OWSTextView

- (instancetype)initWithFrame:(CGRect)frame textContainer:(nullable NSTextContainer *)textContainer
{
    if (self = [super initWithFrame:frame textContainer:textContainer]) {
        [self ows_applyTheme];
    }

    // Setting dataDetectorTypes is expensive.  Do it just once.
    self.dataDetectorTypes = kOWSAllowedDataDetectorTypes;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super initWithCoder:aDecoder]) {
        [self ows_applyTheme];
    }

    self.dataDetectorTypes = kOWSAllowedDataDetectorTypes;

    return self;
}

- (void)ows_applyTheme
{
    self.keyboardAppearance = Theme.keyboardAppearance;
}

// MARK: -

- (void)ensureShouldLinkifyText:(BOOL)shouldLinkifyText
{
    if (shouldLinkifyText) {
        // Setting dataDetectorTypes can be expensive, so we only update it when it's changed.
        if (self.dataDetectorTypes != kOWSAllowedDataDetectorTypes) {
            self.dataDetectorTypes = kOWSAllowedDataDetectorTypes;
        }
    } else {
        // Setting dataDetectorTypes can be expensive, so we only update it when it's changed.
        if (self.dataDetectorTypes != kOWSAllowedDataDetectorTypesExceptLinks) {
            self.dataDetectorTypes = kOWSAllowedDataDetectorTypesExceptLinks;
        }
    }
}

@end

NS_ASSUME_NONNULL_END
