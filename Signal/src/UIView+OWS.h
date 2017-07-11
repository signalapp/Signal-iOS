//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <PureLayout/PureLayout.h>
#import <UIKit/UIKit.h>

// A convenience method for doing responsive layout. Scales between two
// reference values (for iPhone 5 and iPhone 7 Plus) to the current device
// based on screen width, linearly interpolating.
CGFloat ScaleFromIPhone5To7Plus(CGFloat iPhone5Value, CGFloat iPhone7PlusValue);

// A convenience method for doing responsive layout. Scales a reference
// value (for iPhone 5) to the current device based on screen width,
// linearly interpolating through the origin.
CGFloat ScaleFromIPhone5(CGFloat iPhone5Value);

// A set of helper methods for doing layout with PureLayout.
@interface UIView (OWS)

// Pins the width of this view to the width of its superview, with uniform margins.
- (void)autoPinWidthToSuperviewWithMargin:(CGFloat)margin;
- (void)autoPinWidthToSuperview;
// Pins the height of this view to the height of its superview, with uniform margins.
- (void)autoPinHeightToSuperviewWithMargin:(CGFloat)margin;
- (void)autoPinHeightToSuperview;

- (void)autoHCenterInSuperview;
- (void)autoVCenterInSuperview;

- (void)autoPinWidthToWidthOfView:(UIView *)view;
- (void)autoPinHeightToHeightOfView:(UIView *)view;

- (NSLayoutConstraint *)autoPinToSquareAspectRatio;

#pragma mark - Content Hugging and Compression Resistance

- (void)setContentHuggingLow;
- (void)setContentHuggingHigh;
- (void)setContentHuggingHorizontalLow;
- (void)setContentHuggingHorizontalHigh;
- (void)setContentHuggingVerticalLow;
- (void)setContentHuggingVerticalHigh;

- (void)setCompressionResistanceLow;
- (void)setCompressionResistanceHigh;
- (void)setCompressionResistanceHorizontalLow;
- (void)setCompressionResistanceHorizontalHigh;
- (void)setCompressionResistanceVerticalLow;
- (void)setCompressionResistanceVerticalHigh;

#pragma mark - Manual Layout

- (CGFloat)left;
- (CGFloat)right;
- (CGFloat)top;
- (CGFloat)bottom;
- (CGFloat)width;
- (CGFloat)height;

- (void)centerOnSuperview;

#pragma mark - RTL

// For correct right-to-left layout behavior, use "leading" and "trailing",
// not "left" and "right".
//
// NOTE: the margin values are inverted in RTL layouts.
- (BOOL)isRTL;
- (NSArray<NSLayoutConstraint *> *)autoPinLeadingAndTrailingToSuperview;
- (NSLayoutConstraint *)autoPinLeadingToSuperView;
- (NSLayoutConstraint *)autoPinLeadingToSuperViewWithMargin:(CGFloat)margin;
- (NSLayoutConstraint *)autoPinTrailingToSuperView;
- (NSLayoutConstraint *)autoPinTrailingToSuperViewWithMargin:(CGFloat)margin;
- (NSLayoutConstraint *)autoPinLeadingToTrailingOfView:(UIView *)view;
- (NSLayoutConstraint *)autoPinLeadingToTrailingOfView:(UIView *)view margin:(CGFloat)margin;
- (NSLayoutConstraint *)autoPinLeadingToView:(UIView *)view;
- (NSLayoutConstraint *)autoPinLeadingToView:(UIView *)view margin:(CGFloat)margin;
- (NSLayoutConstraint *)autoPinTrailingToView:(UIView *)view;
- (NSLayoutConstraint *)autoPinTrailingToView:(UIView *)view margin:(CGFloat)margin;
// Return Right on LTR and Right on RTL.
- (NSTextAlignment)textAlignmentUnnatural;
// Leading and trailing anchors honor layout margins.
// When using a UIView as a "div" to structure layout, we don't want it to have margins.
+ (UIView *)containerView;
- (void)setHLayoutMargins:(CGFloat)value;

#pragma mark - Formatting

+ (NSString *)formatInt:(int)value;

#pragma mark - Debugging

- (void)addBorderWithColor:(UIColor *)color;
- (void)addRedBorder;

// Add red border to self, and all subviews recursively.
- (void)addRedBorderRecursively;

@end
