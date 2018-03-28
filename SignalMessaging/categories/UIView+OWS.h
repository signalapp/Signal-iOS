//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <PureLayout/PureLayout.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

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
// Pins the height of this view to the height of its superview, with uniform margins.
- (NSArray<NSLayoutConstraint *> *)autoPinHeightToSuperviewWithMargin:(CGFloat)margin;
- (NSArray<NSLayoutConstraint *> *)autoPinHeightToSuperview;

- (NSArray<NSLayoutConstraint *> *)autoPinToSuperviewEdges;

- (NSLayoutConstraint *)autoHCenterInSuperview;
- (NSLayoutConstraint *)autoVCenterInSuperview;

- (void)autoPinWidthToWidthOfView:(UIView *)view;
- (void)autoPinHeightToHeightOfView:(UIView *)view;

- (NSLayoutConstraint *)autoPinToSquareAspectRatio;
- (NSLayoutConstraint *)autoPinToAspectRatio:(CGFloat)ratio;

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
// These methods use layoutMarginsGuide anchors, which behave differently than
// the PureLayout alternatives you indicated. Honoring layoutMargins is
// particularly important in cell layouts, where it lets us align with the
// complicated built-in behavior of table and collection view cells' default
// contents.
//
// NOTE: the margin values are inverted in RTL layouts.
- (BOOL)isRTL;
- (NSArray<NSLayoutConstraint *> *)autoPinLeadingAndTrailingToSuperview;
- (NSLayoutConstraint *)autoPinLeadingToSuperview;
- (NSLayoutConstraint *)autoPinLeadingToSuperviewWithMargin:(CGFloat)margin;
- (NSLayoutConstraint *)autoPinTrailingToSuperview;
- (NSLayoutConstraint *)autoPinTrailingToSuperviewWithMargin:(CGFloat)margin;

- (NSLayoutConstraint *)autoPinTopToSuperview;
- (NSLayoutConstraint *)autoPinTopToSuperviewWithMargin:(CGFloat)margin;
- (NSLayoutConstraint *)autoPinBottomToSuperview;
- (NSLayoutConstraint *)autoPinBottomToSuperviewWithMargin:(CGFloat)margin;

- (NSLayoutConstraint *)autoPinLeadingToTrailingOfView:(UIView *)view;
- (NSLayoutConstraint *)autoPinLeadingToTrailingOfView:(UIView *)view margin:(CGFloat)margin;
- (NSLayoutConstraint *)autoPinTrailingToLeadingOfView:(UIView *)view;
- (NSLayoutConstraint *)autoPinTrailingToLeadingOfView:(UIView *)view margin:(CGFloat)margin;
- (NSLayoutConstraint *)autoPinLeadingToView:(UIView *)view;
- (NSLayoutConstraint *)autoPinLeadingToView:(UIView *)view margin:(CGFloat)margin;
- (NSLayoutConstraint *)autoPinTrailingToView:(UIView *)view;
- (NSLayoutConstraint *)autoPinTrailingToView:(UIView *)view margin:(CGFloat)margin;
// Return Right on LTR and Left on RTL.
- (NSTextAlignment)textAlignmentUnnatural;
// Leading and trailing anchors honor layout margins.
// When using a UIView as a "div" to structure layout, we don't want it to have margins.
- (void)setHLayoutMargins:(CGFloat)value;

#pragma mark - Containers

+ (UIView *)containerView;

+ (UIView *)verticalStackWithSubviews:(NSArray<UIView *> *)subviews spacing:(int)spacing;

#pragma mark - Debugging

- (void)addBorderWithColor:(UIColor *)color;
- (void)addRedBorder;

// Add red border to self, and all subviews recursively.
- (void)addRedBorderRecursively;

#ifdef DEBUG
- (void)logFrameLater;
- (void)logFrameLaterWithLabel:(NSString *)label;
- (void)logHierarchyUpwardLaterWithLabel:(NSString *)label;
#endif

@end

//#pragma mark -
//
//@interface NSLayoutConstraint (OWS)
//
//- (NSLayoutConstraint *)withLowPriority;
//- (NSLayoutConstraint *)withHighPriority;
//
//@end
//
//#pragma mark -
//
//@interface NSArray (OWSLayout)
//
//- (NSArray *)withLowPriorities;
//- (NSArray *)withHighPriorities;
//
//@end

NS_ASSUME_NONNULL_END
