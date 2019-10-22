//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, OWSSearchBarThemeOverride) {
    OWSSearchBarThemeOverride_None,
    OWSSearchBarThemeOverride_SecondaryBar
};

@interface OWSSearchBar : UISearchBar

+ (void)applyThemeToSearchBar:(UISearchBar *)searchBar;
+ (void)applyThemeToSearchBar:(UISearchBar *)searchBar override:(OWSSearchBarThemeOverride)type;

- (void)overrideTheme:(OWSSearchBarThemeOverride)type;

@end

NS_ASSUME_NONNULL_END
