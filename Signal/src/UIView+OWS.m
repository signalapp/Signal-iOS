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
    // TODO:
}

- (void)autoPinWidthToSuperview
{
    [self autoPinEdge:ALEdgeLeft toEdge:ALEdgeLeft ofView:self.superview];
    [self autoPinEdge:ALEdgeRight toEdge:ALEdgeRight ofView:self.superview];
}

- (void)autoPinLeadingAndTrailingToSuperview
{
    [self autoPinLeadingToSuperView];
    [self autoPinTrailingToSuperView];
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

- (void)autoPinWidthToWidthOfView:(UIView *)view
{
    OWSAssert(view);

    [self autoPinEdge:ALEdgeLeft toEdge:ALEdgeLeft ofView:view];
    [self autoPinEdge:ALEdgeRight toEdge:ALEdgeRight ofView:view];
}

- (void)autoPinHeightToHeightOfView:(UIView *)view
{
    OWSAssert(view);

    [self autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:view];
    [self autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:view];
}

- (NSLayoutConstraint *)autoPinToSquareAspectRatio
{
    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint = [NSLayoutConstraint constraintWithItem:self
                                                                  attribute:NSLayoutAttributeWidth
                                                                  relatedBy:NSLayoutRelationEqual
                                                                     toItem:self
                                                                  attribute:NSLayoutAttributeHeight
                                                                 multiplier:1.f
                                                                   constant:0.f];
    [constraint autoInstall];
    return constraint;
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

#pragma mark - Manual Layout

- (CGFloat)left
{
    return self.frame.origin.x;
}

- (CGFloat)right
{
    return self.frame.origin.x + self.frame.size.width;
}

- (CGFloat)top
{
    return self.frame.origin.y;
}

- (CGFloat)bottom
{
    return self.frame.origin.y + self.frame.size.height;
}

- (CGFloat)width
{
    return self.frame.size.width;
}

- (CGFloat)height
{
    return self.frame.size.height;
}

- (void)centerOnSuperview
{
    OWSAssert(self.superview);

    self.frame = CGRectMake(round((self.superview.width - self.width) * 0.5f),
        round((self.superview.height - self.height) * 0.5f),
        self.width,
        self.height);
}

#pragma mark - RTL

- (BOOL)isRTL
{
    return ([UIView userInterfaceLayoutDirectionForSemanticContentAttribute:self.semanticContentAttribute]
        == UIUserInterfaceLayoutDirectionRightToLeft);
}

- (CGFloat)rtlSafeConstant:(CGFloat)value
{
    return (self.isRTL ? -value : value);
}

- (NSLayoutConstraint *)autoPinLeadingToSuperView
{
    return [self autoPinLeadingToSuperViewWithMargin:0];
}

- (NSLayoutConstraint *)autoPinLeadingToSuperViewWithMargin:(CGFloat)margin
{
    NSLayoutConstraint *constraint =
        [self.leadingAnchor constraintEqualToAnchor:self.superview.layoutMarginsGuide.leadingAnchor constant:margin];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinTrailingToSuperView
{
    return [self autoPinTrailingToSuperViewWithMargin:0];
}

- (NSLayoutConstraint *)autoPinTrailingToSuperViewWithMargin:(CGFloat)margin
{
    NSLayoutConstraint *constraint =
        [self.trailingAnchor constraintEqualToAnchor:self.superview.layoutMarginsGuide.trailingAnchor
                                            constant:[self rtlSafeConstant:margin]];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinLeadingToTrailingOfView:(UIView *)view
{
    OWSAssert(view);

    NSLayoutConstraint *constraint = [self autoPinLeadingToTrailingOfView:view margin:0];
}

- (NSLayoutConstraint *)autoPinLeadingToTrailingOfView:(UIView *)view margin:(CGFloat)margin
{
    OWSAssert(view);

    NSLayoutConstraint *constraint = [self.leadingAnchor constraintEqualToAnchor:view.trailingAnchor constant:margin];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinLeadingToView:(UIView *)view
{
    OWSAssert(view);

    return [self autoPinLeadingToView:view margin:0];
}

- (NSLayoutConstraint *)autoPinLeadingToView:(UIView *)view margin:(CGFloat)margin
{
    OWSAssert(view);

    NSLayoutConstraint *constraint =
        [self.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:[self rtlSafeConstant:margin]];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinTrailingToView:(UIView *)view
{
    OWSAssert(view);

    return [self autoPinTrailingToView:view margin:0];
}

- (NSLayoutConstraint *)autoPinTrailingToView:(UIView *)view margin:(CGFloat)margin
{
    OWSAssert(view);

    NSLayoutConstraint *constraint =
        [self.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:[self rtlSafeConstant:margin]];
    constraint.active = YES;
    return constraint;
}

- (NSTextAlignment)textAlignmentUnnatural
{
    return (self.isRTL ? NSTextAlignmentLeft : NSTextAlignmentRight);
}

+ (UIView *)containerView
{
    UIView *view = [UIView new];
    // Leading and trailing anchors honor layout margins.
    // When using a UIView as a "div" to structure layout, we don't want it to have margins.
    view.layoutMargins = UIEdgeInsetsMake(0, 0, 0, 0);
    return view;
}

- (void)setHLayoutMargins:(CGFloat)value
{
    UIEdgeInsets layoutMargins = self.layoutMargins;
    layoutMargins.left = value;
    layoutMargins.right = value;
    self.layoutMargins = layoutMargins;
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
