//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSearchBar.h"
#import "Theme.h"
#import "UIView+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSSearchBar

- (instancetype)init
{
    if (self = [super init]) {
        [self ows_configure];
    }

    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self ows_configure];
    }

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super initWithCoder:aDecoder]) {
        [self ows_configure];
    }

    return self;
}

- (void)ows_configure
{
    [self ows_applyTheme];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange:)
                                                 name:ThemeDidChangeNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)ows_applyTheme
{
    OWSAssertIsOnMainThread();

    self.searchBarStyle = UISearchBarStyleMinimal;
    self.backgroundColor = Theme.searchBarBackgroundColor;
    self.barTintColor = Theme.backgroundColor;
    self.barStyle = Theme.barStyle;
    self.searchBarStyle = Theme.searchBarStyle;

    [self traverseViewHierarchyWithVisitor:^(UIView *view) {
        if ([view isKindOfClass:[UITextField class]]) {
            UITextField *textField = (UITextField *)view;
            textField.keyboardAppearance
                = (Theme.isDarkThemeEnabled ? UIKeyboardAppearanceDark : UIKeyboardAppearanceDefault);
        }
    }];
}

- (void)themeDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self ows_applyTheme];
}

@end

NS_ASSUME_NONNULL_END
