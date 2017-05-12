//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMath.h"
#import "UIView+OWS.h"

static inline CGFloat ScreenShortDimension()
{
    return MIN([UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
}

static const CGFloat kIPhone5ScreenWidth = 320.f;
static const CGFloat kIPhone7PlusScreenWidth = 414.f;

CGFloat ScaleFromIPhone5To7Plus(CGFloat iPhone5Value, CGFloat iPhone7PlusValue)
{
    CGFloat screenShortDimension = ScreenShortDimension();
    return round(CGFloatLerp(iPhone5Value,
        iPhone7PlusValue,
        CGFloatInverseLerp(screenShortDimension, kIPhone5ScreenWidth, kIPhone7PlusScreenWidth)));
}

CGFloat ScaleFromIPhone5(CGFloat iPhone5Value)
{
    CGFloat screenShortDimension = ScreenShortDimension();
    return round(iPhone5Value * screenShortDimension / kIPhone5ScreenWidth);
}

#pragma mark -

@implementation UIView (OWS)

- (void)autoPinWidthToSuperviewWithMargin:(CGFloat)margin
{
    [self autoPinEdge:ALEdgeLeft toEdge:ALEdgeLeft ofView:self.superview withOffset:+margin];
    [self autoPinEdge:ALEdgeRight toEdge:ALEdgeRight ofView:self.superview withOffset:-margin];
}

- (void)autoPinWidthToSuperview
{
    [self autoPinEdge:ALEdgeLeft toEdge:ALEdgeLeft ofView:self.superview];
    [self autoPinEdge:ALEdgeRight toEdge:ALEdgeRight ofView:self.superview];
}

- (void)autoPinHeightToSuperviewWithMargin:(CGFloat)margin
{
    [self autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:self.superview withOffset:+margin];
    [self autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:self.superview withOffset:-margin];
}

- (void)autoPinHeightToSuperview
{
    [self autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:self.superview];
    [self autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:self.superview];
}

- (void)autoHCenterInSuperview
{
    [self autoAlignAxis:ALAxisVertical toSameAxisOfView:self.superview];
}

- (void)autoVCenterInSuperview
{
    [self autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.superview];
}

#pragma mark - Content Hugging and Compression Resistance

- (void)setContentHuggingLow
{
    [self setContentHuggingHorizontalLow];
    [self setContentHuggingVerticalLow];
}

- (void)setContentHuggingHigh
{
    [self setContentHuggingHorizontalHigh];
    [self setContentHuggingVerticalHigh];
}

- (void)setContentHuggingHorizontalLow
{
    [self setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
}

- (void)setContentHuggingHorizontalHigh
{
    [self setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
}

- (void)setContentHuggingVerticalLow
{
    [self setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
}

- (void)setContentHuggingVerticalHigh
{
    [self setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
}

- (void)setCompressionResistanceLow
{
    [self setCompressionResistanceHorizontalLow];
    [self setCompressionResistanceVerticalLow];
}

- (void)setCompressionResistanceHigh
{
    [self setCompressionResistanceHorizontalHigh];
    [self setCompressionResistanceVerticalHigh];
}

- (void)setCompressionResistanceHorizontalLow
{
    [self setContentCompressionResistancePriority:0 forAxis:UILayoutConstraintAxisHorizontal];
}

- (void)setCompressionResistanceHorizontalHigh
{
    [self setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
}

- (void)setCompressionResistanceVerticalLow
{
    [self setContentCompressionResistancePriority:0 forAxis:UILayoutConstraintAxisVertical];
}

- (void)setCompressionResistanceVerticalHigh
{
    [self setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
}

#pragma mark - Debugging

- (void)addBorderWithColor:(UIColor *)color
{
    self.layer.borderColor = color.CGColor;
    self.layer.borderWidth = 1;
}

- (void)addRedBorder
{
    [self addBorderWithColor:[UIColor redColor]];
}

- (void)addRedBorderRecursively
{
    [self addRedBorder];
    for (UIView *subview in self.subviews) {
        [subview addRedBorderRecursively];
    }
}

@end
