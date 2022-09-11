//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(NSUInteger, ThemeMode) {
    ThemeMode_System,
    ThemeMode_Light,
    ThemeMode_Dark,
};

extern NSString *const ThemeDidChangeNotification;

@class SDSKeyValueStore;

@interface Theme : NSObject

+ (SDSKeyValueStore *)keyValueStore;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@property (class, readonly, atomic) BOOL isDarkThemeEnabled;

+ (ThemeMode)getOrFetchCurrentTheme;
+ (void)setCurrentTheme:(ThemeMode)mode;
+ (void)systemThemeChanged;

#if TESTABLE_BUILD
+ (void)setIsDarkThemeEnabledForTests:(BOOL)value;
#endif

#pragma mark - Global App Colors

@property (class, readonly, nonatomic) UIColor *backgroundColor;
@property (class, readonly, nonatomic) UIColor *secondaryBackgroundColor;
@property (class, readonly, nonatomic) UIColor *washColor;
@property (class, readonly, nonatomic) UIColor *primaryTextColor;
@property (class, readonly, nonatomic) UIColor *primaryIconColor;
@property (class, readonly, nonatomic) UIColor *secondaryTextAndIconColor;
@property (class, readonly, nonatomic) UIColor *ternaryTextColor;
@property (class, readonly, nonatomic) UIColor *boldColor;
@property (class, readonly, nonatomic) UIColor *middleGrayColor;
@property (class, readonly, nonatomic) UIColor *placeholderColor;
@property (class, readonly, nonatomic) UIColor *hairlineColor;
@property (class, readonly, nonatomic) UIColor *outlineColor;
@property (class, readonly, nonatomic) UIColor *backdropColor;

@property (class, readonly, nonatomic) UIColor *navbarBackgroundColor;
@property (class, readonly, nonatomic) UIColor *navbarTitleColor;

@property (class, readonly, nonatomic) UIColor *toolbarBackgroundColor;
@property (class, readonly, nonatomic) UIColor *conversationInputBackgroundColor;

@property (class, readonly, nonatomic) UIColor *attachmentKeyboardItemBackgroundColor;
@property (class, readonly, nonatomic) UIColor *attachmentKeyboardItemImageColor;

@property (class, readonly, nonatomic) UIColor *conversationButtonBackgroundColor;
@property (class, readonly, nonatomic) UIColor *conversationButtonTextColor;

@property (class, readonly, nonatomic) UIColor *cellSelectedColor;
@property (class, readonly, nonatomic) UIColor *cellSeparatorColor;

@property (class, readonly, nonatomic) UIColor *cursorColor;

// For accessibility:
//
// * Flat areas (e.g. button backgrounds) should use UIColor.ows_accentBlueColor.
// * Fine detail (e.g., text, non-filled icons) should use Theme.accentBlueColor.
//   It is brighter in dark mode, improving legibility.
@property (class, readonly, nonatomic) UIColor *accentBlueColor;

@property (class, readonly, nonatomic) UIColor *tableCellBackgroundColor;
@property (class, readonly, nonatomic) UIColor *tableViewBackgroundColor;

@property (class, readonly, nonatomic) UIColor *tableCell2BackgroundColor;
@property (class, readonly, nonatomic) UIColor *tableCell2PresentedBackgroundColor;
@property (class, readonly, nonatomic) UIColor *tableCell2SelectedBackgroundColor;
@property (class, readonly, nonatomic) UIColor *tableCell2SelectedBackgroundColor2;
@property (class, readonly, nonatomic) UIColor *tableCell2MultiSelectedBackgroundColor;
@property (class, readonly, nonatomic) UIColor *tableCell2PresentedSelectedBackgroundColor;
@property (class, readonly, nonatomic) UIColor *tableView2BackgroundColor;
@property (class, readonly, nonatomic) UIColor *tableView2PresentedBackgroundColor;
@property (class, readonly, nonatomic) UIColor *tableView2SeparatorColor;
@property (class, readonly, nonatomic) UIColor *tableView2PresentedSeparatorColor;

@property (class, readonly, nonatomic) UIColor *darkThemeTableCell2BackgroundColor;
@property (class, readonly, nonatomic) UIColor *darkThemeTableCell2PresentedBackgroundColor;
@property (class, readonly, nonatomic) UIColor *darkThemeTableCell2SelectedBackgroundColor;
@property (class, readonly, nonatomic) UIColor *darkThemeTableCell2SelectedBackgroundColor2;
@property (class, readonly, nonatomic) UIColor *darkThemeTableCell2MultiSelectedBackgroundColor;
@property (class, readonly, nonatomic) UIColor *darkThemeTableCell2PresentedSelectedBackgroundColor;
@property (class, readonly, nonatomic) UIColor *darkThemeTableView2BackgroundColor;
@property (class, readonly, nonatomic) UIColor *darkThemeTableView2PresentedBackgroundColor;
@property (class, readonly, nonatomic) UIColor *darkThemeTableView2SeparatorColor;
@property (class, readonly, nonatomic) UIColor *darkThemeTableView2PresentedSeparatorColor;

// In some contexts, e.g. media viewing/sending, we always use "dark theme" UI regardless of the
// users chosen theme.
@property (class, readonly, nonatomic) UIColor *darkThemeNavbarIconColor;
@property (class, readonly, nonatomic) UIColor *darkThemeNavbarBackgroundColor;
@property (class, readonly, nonatomic) UIColor *darkThemeBackgroundColor;
@property (class, readonly, nonatomic) UIColor *darkThemePrimaryColor;
@property (class, readonly, nonatomic) UIColor *lightThemePrimaryColor;
@property (class, readonly, nonatomic) UIColor *darkThemeSecondaryTextAndIconColor;
@property (class, readonly, nonatomic) UIBlurEffect *darkThemeBarBlurEffect;
@property (class, readonly, nonatomic) UIColor *galleryHighlightColor;
@property (class, readonly, nonatomic) UIColor *darkThemeWashColor;

#pragma mark -

@property (class, readonly, nonatomic) UIBarStyle barStyle;
@property (class, readonly, nonatomic) UIColor *searchFieldBackgroundColor;
@property (class, readonly, nonatomic) UIColor *searchFieldElevatedBackgroundColor;
@property (class, readonly, nonatomic) UIBlurEffect *barBlurEffect;
@property (class, readonly, nonatomic) UIKeyboardAppearance keyboardAppearance;
@property (class, readonly, nonatomic) UIColor *keyboardBackgroundColor;
@property (class, readonly, nonatomic) UIKeyboardAppearance darkThemeKeyboardAppearance;

#pragma mark -

@property (class, readonly, nonatomic) UIColor *toastForegroundColor;
@property (class, readonly, nonatomic) UIColor *toastBackgroundColor;

@property (class, readonly, nonatomic) UIColor *scrollButtonBackgroundColor;

@end

NS_ASSUME_NONNULL_END
