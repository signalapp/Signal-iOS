//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSSearchBar.h"
#import "Theme.h"
#import "UIView+OWS.h"
#import <SignalMessaging/SignalMessaging-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSearchBar ()

@property (nonatomic) OWSSearchBarStyle currentStyle;

@end

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
    _currentStyle = OWSSearchBarStyle_Default;

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
    [self.class applyThemeToSearchBar:self style:self.currentStyle];
}

+ (void)applyThemeToSearchBar:(UISearchBar *)searchBar
{
    [self applyThemeToSearchBar:searchBar style:OWSSearchBarStyle_Default];
}

+ (void)applyThemeToSearchBar:(UISearchBar *)searchBar style:(OWSSearchBarStyle)style
{
    OWSAssertIsOnMainThread();

    UIColor *foregroundColor = Theme.secondaryTextAndIconColor;
    searchBar.barTintColor = Theme.backgroundColor;
    searchBar.tintColor = Theme.secondaryTextAndIconColor;
    searchBar.barStyle = Theme.barStyle;

    // Hide searchBar border.
    // Alternatively we could hide the border by using `UISearchBarStyleMinimal`, but that causes an issue when toggling
    // from light -> dark -> light theme wherein the textField background color appears darker than it should
    // (regardless of our re-setting textfield.backgroundColor below).
    searchBar.backgroundImage = [UIImage new];

    if (Theme.isDarkThemeEnabled) {
        UIImage *clearImage = [UIImage imageNamed:@"searchbar_clear"];
        [searchBar setImage:[clearImage asTintedImageWithColor:foregroundColor]
            forSearchBarIcon:UISearchBarIconClear
                       state:UIControlStateNormal];

        UIImage *searchImage = [UIImage imageNamed:@"searchbar_search"];
        [searchBar setImage:[searchImage asTintedImageWithColor:foregroundColor]
            forSearchBarIcon:UISearchBarIconSearch
                       state:UIControlStateNormal];
    } else {
        [searchBar setImage:nil forSearchBarIcon:UISearchBarIconClear state:UIControlStateNormal];

        [searchBar setImage:nil forSearchBarIcon:UISearchBarIconSearch state:UIControlStateNormal];
    }

    UIColor *searchFieldBackgroundColor = Theme.searchFieldBackgroundColor;
    if (style == OWSSearchBarStyle_SecondaryBar) {
        searchFieldBackgroundColor = Theme.isDarkThemeEnabled ? UIColor.ows_gray95Color : UIColor.ows_gray05Color;
    }

    [searchBar traverseViewHierarchyDownwardWithVisitor:^(UIView *view) {
        if ([view isKindOfClass:[UITextField class]]) {
            UITextField *textField = (UITextField *)view;
            textField.backgroundColor = searchFieldBackgroundColor;
            textField.textColor = Theme.primaryTextColor;
            textField.keyboardAppearance = Theme.keyboardAppearance;
        }
    }];
}

- (void)switchToStyle:(OWSSearchBarStyle)style
{
    self.currentStyle = style;
    [self ows_applyTheme];
}

- (void)themeDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self ows_applyTheme];
}

@end

NS_ASSUME_NONNULL_END
