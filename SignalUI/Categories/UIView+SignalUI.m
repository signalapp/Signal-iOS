//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "UIView+SignalUI.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/OWSMath.h>
#import <SignalUI/SignalUI-Swift.h>

NS_ASSUME_NONNULL_BEGIN

static inline CGFloat ApplicationShortDimension(void)
{
    return MIN(CurrentAppContext().frame.size.width, CurrentAppContext().frame.size.height);
}

static const CGFloat kIPhone5ScreenWidth = 320.f;
static const CGFloat kIPhone7PlusScreenWidth = 414.f;

CGFloat ScaleFromIPhone5To7Plus(CGFloat iPhone5Value, CGFloat iPhone7PlusValue)
{
    CGFloat applicationShortDimension = ApplicationShortDimension();
    return (CGFloat)round(CGFloatLerp(iPhone5Value,
        iPhone7PlusValue,
        CGFloatClamp01(CGFloatInverseLerp(applicationShortDimension, kIPhone5ScreenWidth, kIPhone7PlusScreenWidth))));
}

CGFloat ScaleFromIPhone5(CGFloat iPhone5Value)
{
    CGFloat applicationShortDimension = ApplicationShortDimension();
    return (CGFloat)round(iPhone5Value * applicationShortDimension / kIPhone5ScreenWidth);
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
    return [self autoPinWidthToSuperviewMarginsWithRelation:NSLayoutRelationEqual];
}

- (NSArray<NSLayoutConstraint *> *)autoPinWidthToSuperview
{
    return [self autoPinWidthToSuperviewWithRelation:NSLayoutRelationEqual];
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
    return [self autoPinHeightToSuperviewWithRelation:NSLayoutRelationEqual];
}

- (NSArray<NSLayoutConstraint *> *)autoPinHeightToSuperviewMargins
{
    return [self autoPinHeightToSuperviewMarginsWithRelation:NSLayoutRelationEqual];
}

- (NSLayoutConstraint *)autoHCenterInSuperview
{
    return [self autoAlignAxis:ALAxisVertical toSameAxisOfView:self.superview];
}

- (NSLayoutConstraint *)autoVCenterInSuperview
{
    return [self autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.superview];
}

- (void)autoPinEdgesToEdgesOfView:(UIView *)view
{
    OWSAssertDebug(view);

    [self autoPinEdge:ALEdgeLeft toEdge:ALEdgeLeft ofView:view];
    [self autoPinEdge:ALEdgeRight toEdge:ALEdgeRight ofView:view];
    [self autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:view];
    [self autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:view];
}

- (void)autoPinHorizontalEdgesToEdgesOfView:(UIView *)view
{
    OWSAssertDebug(view);

    [self autoPinEdge:ALEdgeLeft toEdge:ALEdgeLeft ofView:view];
    [self autoPinEdge:ALEdgeRight toEdge:ALEdgeRight ofView:view];
}

- (void)autoPinVerticalEdgesToEdgesOfView:(UIView *)view
{
    OWSAssertDebug(view);

    [self autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:view];
    [self autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:view];
}

- (NSLayoutConstraint *)autoPinToSquareAspectRatio
{
    return [self autoPinToAspectRatio:1.0];
}

- (NSLayoutConstraint *)autoPinToAspectRatioWithSize:(CGSize)size
{
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
    if (clampedRatio != ratio) {
        OWSFailDebug(@"Invalid aspect ratio: %f for view: %@", ratio, self);
    }

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
    OWSAssertDebug(self.superview);

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

    NSLayoutConstraint *constraint = [self.topAnchor constraintEqualToAnchor:self.superview.layoutMarginsGuide.topAnchor
                                                                    constant:inset];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinLeadingToTrailingEdgeOfView:(UIView *)view
{
    OWSAssertDebug(view);

    return [self autoPinLeadingToTrailingEdgeOfView:view offset:0];
}

- (NSLayoutConstraint *)autoPinLeadingToTrailingEdgeOfView:(UIView *)view offset:(CGFloat)offset
{
    OWSAssertDebug(view);

    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint = [self.leadingAnchor constraintEqualToAnchor:view.trailingAnchor constant:offset];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinTrailingToLeadingEdgeOfView:(UIView *)view
{
    OWSAssertDebug(view);

    return [self autoPinTrailingToLeadingEdgeOfView:view offset:0];
}

- (NSLayoutConstraint *)autoPinTrailingToLeadingEdgeOfView:(UIView *)view offset:(CGFloat)offset
{
    OWSAssertDebug(view);

    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint = [self.trailingAnchor constraintEqualToAnchor:view.leadingAnchor constant:-offset];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinLeadingToEdgeOfView:(UIView *)view
{
    OWSAssertDebug(view);

    return [self autoPinLeadingToEdgeOfView:view offset:0];
}

- (NSLayoutConstraint *)autoPinLeadingToEdgeOfView:(UIView *)view offset:(CGFloat)offset
{
    OWSAssertDebug(view);

    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint = [self.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:offset];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinTrailingToEdgeOfView:(UIView *)view
{
    OWSAssertDebug(view);

    return [self autoPinTrailingToEdgeOfView:view offset:0];
}

- (NSLayoutConstraint *)autoPinTrailingToEdgeOfView:(UIView *)view offset:(CGFloat)margin
{
    OWSAssertDebug(view);

    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint = [self.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:margin];
    constraint.active = YES;
    return constraint;
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
    OWSAssertDebug(view);

    return @[
        [self autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:view],
        [self autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:view],
        [self autoPinEdge:ALEdgeLeading toEdge:ALEdgeLeading ofView:view],
        [self autoPinEdge:ALEdgeTrailing toEdge:ALEdgeTrailing ofView:view],
    ];
}

- (NSArray<NSLayoutConstraint *> *)autoPinToEdgesOfView:(UIView *)view withInsets:(UIEdgeInsets)insets
{
    OWSAssertDebug(view);

    return @[
        [self autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:view withOffset:insets.top],
        [self autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:view withOffset:-insets.bottom],
        [self autoPinEdge:ALEdgeLeading toEdge:ALEdgeLeading ofView:view withOffset:insets.left],
        [self autoPinEdge:ALEdgeTrailing toEdge:ALEdgeTrailing ofView:view withOffset:-insets.right],
    ];
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

- (void)logFrame
{
    [self logFrameWithLabel:@""];
}

- (void)logFrameWithLabel:(NSString *)label
{
    OWSLogVerbose(@"%@ %@ %@ frame: %@, hidden: %d, opacity: %f, layoutMargins: %@",
        label,
        self.class,
        self.accessibilityLabel,
        NSStringFromCGRect(self.frame),
        self.hidden,
        self.layer.opacity,
        NSStringFromUIEdgeInsets(self.layoutMargins));
}

- (void)logFrameLater
{
    [self logFrameLaterWithLabel:@""];
}

- (void)logFrameLaterWithLabel:(NSString *)label
{
    dispatch_async(dispatch_get_main_queue(), ^{ [self logFrameWithLabel:label]; });
}

- (void)logHierarchyUpwardWithLabel:(NSString *)label
{
    NSString *prefix = [NSString stringWithFormat:@"%@ ----", label];
    dispatch_async(dispatch_get_main_queue(), ^{ OWSLogVerbose(@"%@", prefix); });

    [self traverseViewHierarchyUpwardWithVisitor:^(
        UIView *subview) { [subview logFrameWithLabel:[prefix stringByAppendingString:@"\t"]]; }];
}

- (void)logHierarchyUpwardLaterWithLabel:(NSString *)label
{
    NSString *prefix = [NSString stringWithFormat:@"%@ ----", label];
    dispatch_async(dispatch_get_main_queue(), ^{ OWSLogVerbose(@"%@", prefix); });

    [self traverseViewHierarchyUpwardWithVisitor:^(
        UIView *subview) { [subview logFrameLaterWithLabel:[prefix stringByAppendingString:@"\t"]]; }];
}

- (void)logHierarchyDownwardWithLabel:(NSString *)label
{
    NSString *prefix = [NSString stringWithFormat:@"%@ ----", label];
    dispatch_async(dispatch_get_main_queue(), ^{ OWSLogVerbose(@"%@", prefix); });

    [self traverseViewHierarchyDownwardWithVisitor:^(
        UIView *subview) { [subview logFrameWithLabel:[prefix stringByAppendingString:@"\t"]]; }];
}

- (void)logHierarchyDownwardLaterWithLabel:(NSString *)label
{
    NSString *prefix = [NSString stringWithFormat:@"%@ ----", label];
    dispatch_async(dispatch_get_main_queue(), ^{ OWSLogVerbose(@"%@", prefix); });

    [self traverseViewHierarchyDownwardWithVisitor:^(
        UIView *subview) { [subview logFrameLaterWithLabel:[prefix stringByAppendingString:@"\t"]]; }];
}

- (void)traverseViewHierarchyUpwardWithVisitor:(UIViewVisitorBlock)visitor
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(visitor);

    visitor(self);

    UIResponder *_Nullable responder = self;
    while (responder) {
        if ([responder isKindOfClass:[UIView class]]) {
            UIView *view = (UIView *)responder;
            visitor(view);
        }
        responder = responder.nextResponder;
    }
}

- (void)traverseViewHierarchyDownwardWithVisitor:(UIViewVisitorBlock)visitor
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(visitor);

    visitor(self);

    for (UIView *subview in self.subviews) {
        [subview traverseViewHierarchyDownwardWithVisitor:visitor];
    }
}

@end

#pragma mark -

@implementation UIStackView (OWS)

- (void)addHairlineWithColor:(UIColor *)color
{
    [self insertHairlineWithColor:color atIndex:(NSInteger)self.arrangedSubviews.count];
}

- (void)insertHairlineWithColor:(UIColor *)color atIndex:(NSInteger)index
{
    UIView *hairlineView = [[UIView alloc] init];
    hairlineView.backgroundColor = color;
    [hairlineView autoSetDimension:ALDimensionHeight toSize:1];

    [self insertArrangedSubview:hairlineView atIndex:(NSUInteger)index];
}

- (UIView *)addBackgroundViewWithBackgroundColor:(UIColor *)backgroundColor
{
    return [self addBackgroundViewWithBackgroundColor:backgroundColor cornerRadius:0.f];
}

- (UIView *)addBackgroundViewWithBackgroundColor:(UIColor *)backgroundColor cornerRadius:(CGFloat)cornerRadius
{
    UIView *subview = [UIView new];
    subview.backgroundColor = backgroundColor;
    subview.layer.cornerRadius = cornerRadius;
    [self addSubview:subview];
    [subview autoPinEdgesToSuperviewEdges];
    [subview setCompressionResistanceLow];
    [subview setContentHuggingLow];
    [self sendSubviewToBack:subview];
    return subview;
}

- (UIView *)addBorderViewWithColor:(UIColor *)color strokeWidth:(CGFloat)strokeWidth cornerRadius:(CGFloat)cornerRadius
{

    UIView *borderView = [UIView new];
    borderView.userInteractionEnabled = NO;
    borderView.backgroundColor = UIColor.clearColor;
    borderView.opaque = NO;
    borderView.layer.borderColor = color.CGColor;
    borderView.layer.borderWidth = strokeWidth;
    borderView.layer.cornerRadius = cornerRadius;
    [self addSubview:borderView];
    [borderView autoPinEdgesToSuperviewEdges];
    [borderView setCompressionResistanceLow];
    [borderView setContentHuggingLow];
    return borderView;
}

@end

#pragma mark -

CGFloat CGHairlineWidth(void)
{
    return 1.f / UIScreen.mainScreen.scale;
}

CGFloat CGHairlineWidthFraction(CGFloat fraction)
{
    return CGHairlineWidth() * fraction;
}

NS_ASSUME_NONNULL_END
