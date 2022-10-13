//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSTextView.h"
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSTextView

- (instancetype)initWithFrame:(CGRect)frame textContainer:(nullable NSTextContainer *)textContainer
{
    if (self = [super initWithFrame:frame textContainer:textContainer]) {
        [self ows_applyTheme];
    }

    // Do not linkify; we linkify manually.
    self.dataDetectorTypes = UIDataDetectorTypeNone;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super initWithCoder:aDecoder]) {
        [self ows_applyTheme];
    }

    // Do not linkify; we linkify manually.
    self.dataDetectorTypes = UIDataDetectorTypeNone;

    return self;
}

- (void)ows_applyTheme
{
    self.keyboardAppearance = Theme.keyboardAppearance;
}

@end

NS_ASSUME_NONNULL_END
