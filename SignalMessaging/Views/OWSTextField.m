//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
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
    self.keyboardAppearance = (Theme.isDarkThemeEnabled ? UIKeyboardAppearanceDark : UIKeyboardAppearanceDefault);
}

- (BOOL)becomeFirstResponder
{
    BOOL result = [super becomeFirstResponder];

    [self.ows_delegate textFieldDidBecomeFirstResponder:self];

    return result;
}

- (BOOL)resignFirstResponder
{
    BOOL result = [super resignFirstResponder];

    [self.ows_delegate textFieldDidResignFirstResponder:self];

    return result;
}

@end

NS_ASSUME_NONNULL_END
