//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMath.h"
#import "UIView+OWS.h"
#import <SignalServiceKit/AppContext.h>

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

- (NSArray<NSLayoutConstraint *> *)autoPinWidthToSuperviewWithMargin:(CGFloat)margin
{
    NSArray<NSLayoutConstraint *> *result = @[
        [self autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:margin],
        [self autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:margin],
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

- (NSArray<NSLayoutConstraint *> *)autoPinLeadingAndTrailingToSuperview
{
    NSArray<NSLayoutConstraint *> *result = @[
        [self autoPinLeadingToSuperview],
        [self autoPinTrailingToSuperview],
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

- (NSArray<NSLayoutConstraint *> *)autoPinToSuperviewEdges
{
    NSArray<NSLayoutConstraint *> *result = @[
        [self autoPinEdgeToSuperviewEdge:ALEdgeLeft],
        [self autoPinEdgeToSuperviewEdge:ALEdgeRight],
        [self autoPinEdgeToSuperviewEdge:ALEdgeTop],
        [self autoPinEdgeToSuperviewEdge:ALEdgeBottom],
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
    return [self autoPinToAspectRatio:1.0];
}

- (NSLayoutConstraint *)autoPinToAspectRatio:(CGFloat)ratio
{
    // Clamp to ensure view has reasonable aspect ratio.
    CGFloat clampedRatio = Clamp(ratio, 0.05, 95.0);
    if (clampedRatio != ratio) {
        OWSFail(@"Invalid aspect ratio: %f for view: %@", ratio, self);
    }

    self.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *constraint = [NSLayoutConstraint constraintWithItem:self
                                                                  attribute:NSLayoutAttributeWidth
                                                                  relatedBy:NSLayoutRelationEqual
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

- (NSLayoutConstraint *)autoPinLeadingToSuperview
{
    return [self autoPinLeadingToSuperviewWithMargin:0];
}

- (NSLayoutConstraint *)autoPinLeadingToSuperviewWithMargin:(CGFloat)margin
{
    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint =
        [self.leadingAnchor constraintEqualToAnchor:self.superview.layoutMarginsGuide.leadingAnchor constant:margin];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinTrailingToSuperview
{
    return [self autoPinTrailingToSuperviewWithMargin:0];
}

- (NSLayoutConstraint *)autoPinTrailingToSuperviewWithMargin:(CGFloat)margin
{
    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint =
        [self.trailingAnchor constraintEqualToAnchor:self.superview.layoutMarginsGuide.trailingAnchor constant:-margin];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinBottomToSuperview
{
    return [self autoPinBottomToSuperviewWithMargin:0.f];
}

- (NSLayoutConstraint *)autoPinBottomToSuperviewWithMargin:(CGFloat)margin
{
    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint =
        [self.bottomAnchor constraintEqualToAnchor:self.superview.layoutMarginsGuide.bottomAnchor constant:-margin];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinTopToSuperview
{
    return [self autoPinTopToSuperviewWithMargin:0.f];
}

- (NSLayoutConstraint *)autoPinTopToSuperviewWithMargin:(CGFloat)margin
{
    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint =
        [self.topAnchor constraintEqualToAnchor:self.superview.layoutMarginsGuide.topAnchor constant:margin];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinLeadingToTrailingOfView:(UIView *)view
{
    OWSAssert(view);

    return [self autoPinLeadingToTrailingOfView:view margin:0];
}

- (NSLayoutConstraint *)autoPinLeadingToTrailingOfView:(UIView *)view margin:(CGFloat)margin
{
    OWSAssert(view);

    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint = [self.leadingAnchor constraintEqualToAnchor:view.trailingAnchor constant:margin];
    constraint.active = YES;
    return constraint;
}

- (NSLayoutConstraint *)autoPinTrailingToLeadingOfView:(UIView *)view
{
    OWSAssert(view);

    return [self autoPinTrailingToLeadingOfView:view margin:0];
}

- (NSLayoutConstraint *)autoPinTrailingToLeadingOfView:(UIView *)view margin:(CGFloat)margin
{
    OWSAssert(view);

    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint = [self.trailingAnchor constraintEqualToAnchor:view.leadingAnchor constant:-margin];
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

    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint = [self.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:margin];
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

    self.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *constraint = [self.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:margin];
    constraint.active = YES;
    return constraint;
}

- (NSTextAlignment)textAlignmentUnnatural
{
    return (self.isRTL ? NSTextAlignmentLeft : NSTextAlignmentRight);
}

- (void)setHLayoutMargins:(CGFloat)value
{
    UIEdgeInsets layoutMargins = self.layoutMargins;
    layoutMargins.left = value;
    layoutMargins.right = value;
    self.layoutMargins = layoutMargins;
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

- (void)logFrameLater
{
    [self logFrameLaterWithLabel:@""];
}

- (void)logFrameLaterWithLabel:(NSString *)label
{
    dispatch_async(dispatch_get_main_queue(), ^{
        DDLogVerbose(@"%@ %@ frame: %@, hidden: %d, opacity: %f",
            self.logTag,
            label,
            NSStringFromCGRect(self.frame),
            self.hidden,
            self.layer.opacity);
    });
}

- (void)logHierarchyUpwardLaterWithLabel:(NSString *)label
{
    dispatch_async(dispatch_get_main_queue(), ^{
        DDLogVerbose(@"%@ %@ ----", self.logTag, label);
    });

    UIResponder *responder = self;
    while (responder) {
        if ([responder isKindOfClass:[UIView class]]) {
            UIView *view = (UIView *)responder;
            [view logFrameLaterWithLabel:@"\t"];
        }
        responder = responder.nextResponder;
    }
}

@end

NS_ASSUME_NONNULL_END
