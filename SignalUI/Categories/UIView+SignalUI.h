//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <PureLayout/PureLayout.h>
#import <SignalServiceKit/OWSMath.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^UIViewVisitorBlock)(UIView *view);

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
- (NSArray<NSLayoutConstraint *> *)autoPinWidthToSuperviewWithMargin:(CGFloat)margin;
- (NSArray<NSLayoutConstraint *> *)autoPinWidthToSuperview;
- (NSArray<NSLayoutConstraint *> *)autoPinWidthToSuperviewMargins;
// Pins the height of this view to the height of its superview, with uniform margins.
- (NSArray<NSLayoutConstraint *> *)autoPinHeightToSuperviewWithMargin:(CGFloat)margin;
- (NSArray<NSLayoutConstraint *> *)autoPinHeightToSuperview;
- (NSArray<NSLayoutConstraint *> *)autoPinHeightToSuperviewMargins;

- (NSLayoutConstraint *)autoHCenterInSuperview;
- (NSLayoutConstraint *)autoVCenterInSuperview;

- (void)autoPinEdgesToEdgesOfView:(UIView *)view;
- (void)autoPinHorizontalEdgesToEdgesOfView:(UIView *)view;
- (void)autoPinVerticalEdgesToEdgesOfView:(UIView *)view;

- (NSLayoutConstraint *)autoPinToSquareAspectRatio;
- (NSLayoutConstraint *)autoPinToAspectRatioWithSize:(CGSize)size;
- (NSLayoutConstraint *)autoPinToAspectRatio:(CGFloat)ratio;
- (NSLayoutConstraint *)autoPinToAspectRatio:(CGFloat)ratio relation:(NSLayoutRelation)relation;

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

@property (nonatomic, readonly) CGFloat left;
@property (nonatomic, readonly) CGFloat right;
@property (nonatomic, readonly) CGFloat top;
@property (nonatomic, readonly) CGFloat bottom;
@property (nonatomic, readonly) CGFloat width;
@property (nonatomic, readonly) CGFloat height;

- (void)centerOnSuperview;

#pragma mark - RTL

// For correct right-to-left layout behavior, use "leading" and "trailing",
// not "left" and "right".
//
// These methods use layoutMarginsGuide anchors, which behave differently than
// the PureLayout alternatives you indicated. Honoring layoutMargins is
// particularly important in cell layouts, where it lets us align with the
// complicated built-in behavior of table and collection view cells' default
// contents.
//
// NOTE: the margin values are inverted in RTL layouts.

- (NSArray<NSLayoutConstraint *> *)autoPinLeadingAndTrailingToSuperviewMargin;
- (NSLayoutConstraint *)autoPinLeadingToSuperviewMargin;
- (NSLayoutConstraint *)autoPinLeadingToSuperviewMarginWithInset:(CGFloat)margin;
- (NSLayoutConstraint *)autoPinTrailingToSuperviewMargin;
- (NSLayoutConstraint *)autoPinTrailingToSuperviewMarginWithInset:(CGFloat)margin;

- (NSLayoutConstraint *)autoPinTopToSuperviewMargin;
- (NSLayoutConstraint *)autoPinTopToSuperviewMarginWithInset:(CGFloat)margin;
- (NSLayoutConstraint *)autoPinBottomToSuperviewMargin;
- (NSLayoutConstraint *)autoPinBottomToSuperviewMarginWithInset:(CGFloat)margin;

- (NSLayoutConstraint *)autoPinLeadingToTrailingEdgeOfView:(UIView *)view;
- (NSLayoutConstraint *)autoPinLeadingToTrailingEdgeOfView:(UIView *)view offset:(CGFloat)margin;
- (NSLayoutConstraint *)autoPinTrailingToLeadingEdgeOfView:(UIView *)view;
- (NSLayoutConstraint *)autoPinTrailingToLeadingEdgeOfView:(UIView *)view offset:(CGFloat)margin;
- (NSLayoutConstraint *)autoPinLeadingToEdgeOfView:(UIView *)view;
- (NSLayoutConstraint *)autoPinLeadingToEdgeOfView:(UIView *)view offset:(CGFloat)margin;
- (NSLayoutConstraint *)autoPinTrailingToEdgeOfView:(UIView *)view;
- (NSLayoutConstraint *)autoPinTrailingToEdgeOfView:(UIView *)view offset:(CGFloat)margin;
// Return Right on LTR and Left on RTL.
+ (NSTextAlignment)textAlignmentUnnatural;
- (NSTextAlignment)textAlignmentUnnatural;
// Leading and trailing anchors honor layout margins.
// When using a UIView as a "div" to structure layout, we don't want it to have margins.
- (void)setHLayoutMargins:(CGFloat)value;

- (NSArray<NSLayoutConstraint *> *)autoPinToEdgesOfView:(UIView *)view;
- (NSArray<NSLayoutConstraint *> *)autoPinToEdgesOfView:(UIView *)view withInsets:(UIEdgeInsets)insets;

- (void)traverseViewHierarchyUpwardWithVisitor:(UIViewVisitorBlock)visitor;

- (void)traverseViewHierarchyDownwardWithVisitor:(UIViewVisitorBlock)visitor;

#pragma mark - Debugging

- (void)addBorderWithColor:(UIColor *)color;
- (void)addRedBorder;

// Add red border to self, and all subviews recursively.
- (void)addRedBorderRecursively;

#ifdef DEBUG
- (void)logFrame;
- (void)logFrameWithLabel:(NSString *)label;
- (void)logFrameLater;
- (void)logFrameLaterWithLabel:(NSString *)label;
- (void)logHierarchyUpwardWithLabel:(NSString *)label;
- (void)logHierarchyUpwardLaterWithLabel:(NSString *)label;
- (void)logHierarchyDownwardWithLabel:(NSString *)label;
- (void)logHierarchyDownwardLaterWithLabel:(NSString *)label;
#endif

@end

#pragma mark -

@interface UIStackView (OWS)

- (void)addHairlineWithColor:(UIColor *)color;
- (void)insertHairlineWithColor:(UIColor *)color atIndex:(NSInteger)index;

- (UIView *)addBackgroundViewWithBackgroundColor:(UIColor *)backgroundColor;
- (UIView *)addBackgroundViewWithBackgroundColor:(UIColor *)backgroundColor cornerRadius:(CGFloat)cornerRadius;

- (UIView *)addBorderViewWithColor:(UIColor *)color strokeWidth:(CGFloat)strokeWidth cornerRadius:(CGFloat)cornerRadius;

@end

#pragma mark - Macros

CGFloat CGHairlineWidth(void);

/// Primarily useful to adjust border widths to
/// compensate for antialiasing around light
/// color curves on dark backgrounds.
CGFloat CGHairlineWidthFraction(CGFloat);

NS_ASSUME_NONNULL_END
