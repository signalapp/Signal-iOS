//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

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

#pragma mark - Debugging

- (void)addBorderWithColor:(UIColor *)color;
- (void)addRedBorder;

@end
