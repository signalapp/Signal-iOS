//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "UIColor+OWS.h"
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ThemeDidChangeNotification;

@interface Theme : NSObject

- (instancetype)init NS_UNAVAILABLE;

@property (class, readonly, atomic) BOOL isDarkThemeEnabled;

+ (void)setIsDarkThemeEnabled:(BOOL)value;

@property (class, readonly, nonatomic) UIColor *backgroundColor;
@property (class, readonly, nonatomic) UIColor *primaryColor;
@property (class, readonly, nonatomic) UIColor *secondaryColor;
@property (class, readonly, nonatomic) UIColor *boldColor;
@property (class, readonly, nonatomic) UIColor *offBackgroundColor;
@property (class, readonly, nonatomic) UIColor *middleGrayColor;
@property (class, readonly, nonatomic) UIColor *placeholderColor;
@property (class, readonly, nonatomic) UIColor *hairlineColor;

#pragma mark - Global App Colors

@property (class, readonly, nonatomic) UIColor *navbarBackgroundColor;
@property (class, readonly, nonatomic) UIColor *navbarIconColor;
@property (class, readonly, nonatomic) UIColor *navbarTitleColor;

@property (class, readonly, nonatomic) UIColor *toolbarBackgroundColor;

@property (class, readonly, nonatomic) UIColor *conversationButtonBackgroundColor;

@property (class, readonly, nonatomic) UIColor *cellSelectedColor;
@property (class, readonly, nonatomic) UIColor *cellSeparatorColor;

// In some contexts, e.g. media viewing/sending, we always use "dark theme" UI regardless of the
// users chosen theme.
@property (class, readonly, nonatomic) UIColor *darkThemeNavbarIconColor;
@property (class, readonly, nonatomic) UIColor *darkThemeNavbarBackgroundColor;
@property (class, readonly, nonatomic) UIColor *darkThemeBackgroundColor;
@property (class, readonly, nonatomic) UIColor *darkThemePrimaryColor;
@property (class, readonly, nonatomic) UIBlurEffect *darkThemeBarBlurEffect;
@property (class, readonly, nonatomic) UIColor *galleryHighlightColor;

#pragma mark -

@property (class, readonly, nonatomic) UIBarStyle barStyle;
@property (class, readonly, nonatomic) UIColor *searchFieldBackgroundColor;
@property (class, readonly, nonatomic) UIBlurEffect *barBlurEffect;
@property (class, readonly, nonatomic) UIKeyboardAppearance keyboardAppearance;
@property (class, readonly, nonatomic) UIKeyboardAppearance darkThemeKeyboardAppearance;

#pragma mark -

@property (class, readonly, nonatomic) UIColor *toastForegroundColor;
@property (class, readonly, nonatomic) UIColor *toastBackgroundColor;

@property (class, readonly, nonatomic) UIColor *scrollButtonBackgroundColor;

@end

NS_ASSUME_NONNULL_END
