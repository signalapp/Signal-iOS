//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSearchBar.h"
#import "Theme.h"
#import "UIView+OWS.h"
#import <SignalMessaging/SignalMessaging-Swift.h>

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

    UIColor *foregroundColor = Theme.placeholderColor;
    self.barTintColor = Theme.backgroundColor;
    self.barStyle = Theme.barStyle;

    // Hide searchBar border.
    // Alternatively we could hide the border by using `UISearchBarStyleMinimal`, but that causes an issue when toggling
    // from light -> dark -> light theme wherein the textField background color appears darker than it should
    // (regardless of our re-setting textfield.backgroundColor below).
    self.backgroundImage = [UIImage new];

    if (Theme.isDarkThemeEnabled) {
        UIImage *clearImage = [UIImage imageNamed:@"searchbar_clear"];
        [self setImage:[clearImage asTintedImageWithColor:foregroundColor]
            forSearchBarIcon:UISearchBarIconClear
                       state:UIControlStateNormal];

        UIImage *searchImage = [UIImage imageNamed:@"searchbar_search"];
        [self setImage:[searchImage asTintedImageWithColor:foregroundColor]
            forSearchBarIcon:UISearchBarIconSearch
                       state:UIControlStateNormal];
    } else {
        [self setImage:nil forSearchBarIcon:UISearchBarIconClear state:UIControlStateNormal];

        [self setImage:nil forSearchBarIcon:UISearchBarIconSearch state:UIControlStateNormal];
    }

    [self traverseViewHierarchyWithVisitor:^(UIView *view) {
        if ([view isKindOfClass:[UITextField class]]) {
            UITextField *textField = (UITextField *)view;
            textField.backgroundColor = Theme.searchFieldBackgroundColor;
            textField.textColor = Theme.primaryColor;
            textField.keyboardAppearance = Theme.keyboardAppearance;
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
