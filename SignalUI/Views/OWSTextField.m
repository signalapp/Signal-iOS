//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSTextField.h"
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSTextField

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self ows_applyTheme];
    }

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super initWithCoder:aDecoder]) {
        [self ows_applyTheme];
    }

    return self;
}

- (void)ows_applyTheme
{
    self.keyboardAppearance = Theme.keyboardAppearance;
}

@end

NS_ASSUME_NONNULL_END
