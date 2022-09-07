//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "UIView+OWS.h"
#import "OWSMath.h"

#import <SessionUtilitiesKit/AppContext.h>

NS_ASSUME_NONNULL_BEGIN

static inline CGFloat ScreenShortDimension()
{
    return MIN([UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
}

static const CGFloat kIPhone5ScreenWidth = 320.f;
static const CGFloat kIPhone7PlusScreenWidth = 414.f;

CGFloat ScaleFromIPhone5To7Plus(CGFloat iPhone5Value, CGFloat iPhone7PlusValue)
{
    CGFloat screenShortDimension = ScreenShortDimension();
    return (CGFloat)round(CGFloatLerp(iPhone5Value,
        iPhone7PlusValue,
        CGFloatClamp01(CGFloatInverseLerp(screenShortDimension, kIPhone5ScreenWidth, kIPhone7PlusScreenWidth))));
}

CGFloat ScaleFromIPhone5(CGFloat iPhone5Value)
{
    CGFloat screenShortDimension = ScreenShortDimension();
    return (CGFloat)round(iPhone5Value * screenShortDimension / kIPhone5ScreenWidth);
}

#pragma mark -

@implementation UIView (OWS)

- (NSArray<NSLayoutConstraint *> *)autoPinWidthToSuperviewWithMargin:(CGFloat)margin
{
    NSArray<NSLayoutConstraint *> *result = @[
        [self autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:margin],
        [self autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:margin],
    ];
    return result;
}

- (NSArray<NSLayoutConstraint *> *)autoPinWidthToSuperviewMargins
{
    NSArray<NSLayoutConstraint *> *result = @[
        [self autoPinEdgeToSuperviewMargin:ALEdgeLeading],
        [self autoPinEdgeToSuperviewMargin:ALEdgeTrailing],
    ];
    return result;
}

- (NSArray<NSLayoutConstraint *> *)autoPinWidthToSuperview
{
    NSArray<NSLayoutConstraint *> *result = @[
        [self autoPinEdgeToSuperviewEdge:ALEdgeLeft],
        [self autoPinEdgeToSuperviewEdge:ALEdgeRight],
    ];
    return result;
}

- (NSArray<NSLayoutConstraint *> *)autoPinLeadingAndTrailingToSuperviewMargin
{
    NSArray<NSLayoutConstraint *> *result = @[
        [self autoPinLeadingToSuperviewMargin],
        [self autoPinTrailingToSuperviewMargin],
    ];
    return result;
}

- (NSArray<NSLayoutConstraint *> *)autoPinHeightToSuperviewWithMargin:(CGFloat)margin
{
    NSArray<NSLayoutConstraint *> *result = @[
        [self autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:margin],
        [self autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:margin],
    ];
    return result;
}

- (NSArray<NSLayoutConstraint *> *)autoPinHeightToSuperview
{
    NSArray<NSLayoutConstraint *> *result = @[
        [self autoPinEdgeToSuperviewEdge:ALEdgeTop],
        [self autoPinEdgeToSuperviewEdge:ALEdgeBottom],
    ];
    return result;
}

- (NSArray<NSLayoutConstraint *> *)ows_autoPinToSuperviewEdges
{
    NSArray<NSLayoutConstraint *> *result = @[
        [self autoPinEdgeToSuperviewEdge:ALEdgeLeft],
        [self autoPinEdgeToSuperviewEdge:ALEdgeRight],
        [self autoPinEdgeToSuperviewEdge:ALEdgeTop],
        [self autoPinEdgeToSuperviewEdge:ALEdgeBottom],
    ];
    return result;
}

- (NSArray<NSLayoutConstraint *> *)ows_autoPinToSuperviewMargins
{
    NSArray<NSLayoutConstraint *> *result = @[
        [self autoPinTopToSuperviewMargin],
        [self autoPinLeadingToSuperviewMargin],
        [self autoPinTrailingToSuperviewMargin],
        [self autoPinBottomToSuperviewMargin],
    ];
    return result;
}

- (NSLayoutConstraint *)autoHCenterInSuperview
{
    return [self autoAlignAxis:ALAxisVertical toSameAxisOfView:self.superview];
}

- (NSLayoutConstraint *)autoVCenterInSuperview
{
    return [self autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.superview];
}

- (void)autoPinWidthToWidthOfView:(UIView *)view
{
    [self autoPinEdge:ALEdgeLeft toEdge:ALEdgeLeft ofView:view];
    [self autoPinEdge:ALEdgeRight toEdge:ALEdgeRight ofView:view];
}

- (void)autoPinHeightToHeightOfView:(UIView *)view
{
    [self autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:view];
    [self autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:view];
}

- (NSLayoutConstraint *)autoPinToSquareAspectRatio
{
    return [self autoPinToAspectRatio:1.0];
}

- (NSLayoutConstraint *)autoPinToAspectRatioWithSize:(CGSize)size {
    return [self autoPinToAspectRatio:size.width / size.height];
}

- (NSLayoutConstraint *)autoPinToAspectRatio:(CGFloat)ratio
{
    return [self autoPinToAspectRatio:ratio relation:NSLayoutRelationEqual];
}

- (NSLayoutConstraint *)autoPinToAspectRatio:(CGFloat)ratio relation:(NSLayoutRelation)relation
{
    // Clamp to ensure view has reasonable aspect ratio.
    CGFloat clampedRatio = CGFloatClamp(ratio, 0.05f, 95.0f);

    self.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *constraint = [NSLayoutConstraint constraintWithItem:self
                                                                  attribute:NSLayoutAttributeWidth
                                                                  relatedBy:relation
                                                                     toItem:self
                                                                  attribute:NSLayoutAttributeHeight
                                                                 multiplier:clampedRatio
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
    CGFloat x = (CGFloat)round((self.superview.width - self.width) * 0.5f);
    CGFloat y = (CGFloat)round((self.superview.height - self.height) * 0.5f);
    self.frame = CGRectMake(x, y, self.width, self.height);
}

#pragma mark - RTL

- (NSLayoutConstraint *)autoPinLeadingToSuperviewMargin
{
    return [self autoPinLeadingToSuperviewMarginWithInset:0];
}

- (NSLayoutConstraint *)autoPinLeadingToSuperviewMarginWithInset:(CGFloat)inset
{
    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint =
        [self.leadingAnchor constraintEqualToAnchor:self.superview.layoutMarginsGuide.leadingAnchor constant:inset];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinTrailingToSuperviewMargin
{
    return [self autoPinTrailingToSuperviewMarginWithInset:0];
}

- (NSLayoutConstraint *)autoPinTrailingToSuperviewMarginWithInset:(CGFloat)inset
{
    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint =
        [self.trailingAnchor constraintEqualToAnchor:self.superview.layoutMarginsGuide.trailingAnchor constant:-inset];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinBottomToSuperviewMargin
{
    return [self autoPinBottomToSuperviewMarginWithInset:0.f];
}

- (NSLayoutConstraint *)autoPinBottomToSuperviewMarginWithInset:(CGFloat)inset
{
    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint =
        [self.bottomAnchor constraintEqualToAnchor:self.superview.layoutMarginsGuide.bottomAnchor constant:-inset];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinTopToSuperviewMargin
{
    return [self autoPinTopToSuperviewMarginWithInset:0.f];
}

- (NSLayoutConstraint *)autoPinTopToSuperviewMarginWithInset:(CGFloat)inset
{
    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint =
        [self.topAnchor constraintEqualToAnchor:self.superview.layoutMarginsGuide.topAnchor constant:inset];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinLeadingToTrailingEdgeOfView:(UIView *)view
{
    return [self autoPinLeadingToTrailingEdgeOfView:view offset:0];
}

- (NSLayoutConstraint *)autoPinLeadingToTrailingEdgeOfView:(UIView *)view offset:(CGFloat)offset
{
    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint = [self.leadingAnchor constraintEqualToAnchor:view.trailingAnchor constant:offset];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinTrailingToLeadingEdgeOfView:(UIView *)view
{
    return [self autoPinTrailingToLeadingEdgeOfView:view offset:0];
}

- (NSLayoutConstraint *)autoPinTrailingToLeadingEdgeOfView:(UIView *)view offset:(CGFloat)offset
{
    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint = [self.trailingAnchor constraintEqualToAnchor:view.leadingAnchor constant:-offset];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinLeadingToEdgeOfView:(UIView *)view
{
    return [self autoPinLeadingToEdgeOfView:view offset:0];
}

- (NSLayoutConstraint *)autoPinLeadingToEdgeOfView:(UIView *)view offset:(CGFloat)offset
{
    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint = [self.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:offset];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinTrailingToEdgeOfView:(UIView *)view
{
    return [self autoPinTrailingToEdgeOfView:view offset:0];
}

- (NSLayoutConstraint *)autoPinTrailingToEdgeOfView:(UIView *)view offset:(CGFloat)margin
{
    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint = [self.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:margin];
    constraint.active = YES;
    return constraint;
}

- (NSTextAlignment)textAlignmentUnnatural
{
    return (CurrentAppContext().isRTL ? NSTextAlignmentLeft : NSTextAlignmentRight);
}

- (void)setHLayoutMargins:(CGFloat)value
{
    UIEdgeInsets layoutMargins = self.layoutMargins;
    layoutMargins.left = value;
    layoutMargins.right = value;
    self.layoutMargins = layoutMargins;
}

- (NSArray<NSLayoutConstraint *> *)autoPinToEdgesOfView:(UIView *)view
{
    return @[
        [self autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:view],
        [self autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:view],
        [self autoPinEdge:ALEdgeLeading toEdge:ALEdgeLeading ofView:view],
        [self autoPinEdge:ALEdgeTrailing toEdge:ALEdgeTrailing ofView:view],
    ];
}

#pragma mark - Containers

+ (UIView *)containerView
{
    UIView *view = [UIView new];
    // Leading and trailing anchors honor layout margins.
    // When using a UIView as a "div" to structure layout, we don't want it to have margins.
    view.layoutMargins = UIEdgeInsetsZero;
    return view;
}

+ (UIView *)verticalStackWithSubviews:(NSArray<UIView *> *)subviews spacing:(int)spacing
{
    UIView *container = [UIView containerView];
    UIView *_Nullable lastSubview = nil;
    for (UIView *subview in subviews) {
        [container addSubview:subview];
        [subview autoPinWidthToSuperview];
        if (lastSubview) {
            [subview autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:lastSubview withOffset:spacing];
        } else {
            [subview autoPinEdgeToSuperviewEdge:ALEdgeTop];
        }
        lastSubview = subview;
    }
    [lastSubview autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    return container;
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

- (void)traverseViewHierarchyWithVisitor:(UIViewVisitorBlock)visitor
{
    visitor(self);

    for (UIView *subview in self.subviews) {
        [subview traverseViewHierarchyWithVisitor:visitor];
    }
}

@end

#pragma mark -

@implementation UIScrollView (OWS)

- (BOOL)applyScrollViewInsetsFix
{
    return NO;
}

@end

#pragma mark -

@implementation UIAlertAction (OWS)

+ (instancetype)actionWithTitle:(nullable NSString *)title
        accessibilityIdentifier:(nullable NSString *)accessibilityIdentifier
                          style:(UIAlertActionStyle)style
                        handler:(void (^__nullable)(UIAlertAction *action))handler
{
    UIAlertAction *action = [UIAlertAction actionWithTitle:title style:style handler:handler];
    action.accessibilityIdentifier = accessibilityIdentifier;
    return action;
}

@end

#pragma mark -

CGFloat CGHairlineWidth()
{
    return 1.f / UIScreen.mainScreen.scale;
}

NS_ASSUME_NONNULL_END
