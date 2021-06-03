//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSBubbleView.h"
#import "MainAppContext.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

const CGFloat kOWSMessageCellCornerRadius_Large = 18;
const CGFloat kOWSMessageCellCornerRadius_Small = 4;

#pragma mark -

@interface OWSBubbleView ()

@property (nonatomic) CAShapeLayer *maskLayer;
@property (nonatomic) CAShapeLayer *shapeLayer;
@property (nonatomic) CAGradientLayer *gradientLayer;

@end

#pragma mark -

@implementation OWSBubbleView

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.layoutMargins = UIEdgeInsetsZero;
    OWSAssertDebug(self.layer.delegate == self);

    self.shapeLayer = [CAShapeLayer new];
    [self.shapeLayer disableAnimationsWithDelegate];
    [self.layer addSublayer:self.shapeLayer];
    self.shapeLayer.hidden = YES;

    self.gradientLayer = [CAGradientLayer new];
    [self.gradientLayer disableAnimationsWithDelegate];
    [self.layer addSublayer:self.gradientLayer];
    self.gradientLayer.hidden = YES;

    self.layer.masksToBounds = YES;
    self.maskLayer = [CAShapeLayer new];
    [self.maskLayer disableAnimationsWithDelegate];

    self.translatesAutoresizingMaskIntoConstraints = NO;

    return self;
}

- (void)dealloc
{
    OWSAssertIsOnMainThread();
}

- (void)setFrame:(CGRect)frame
{
    // We only need to update our layers if the _size_ of this view
    // changes since the contents of the layers are in local coordinates.
    BOOL didChangeSize = !CGSizeEqualToSize(self.frame.size, frame.size);

    [super setFrame:frame];

    if (didChangeSize) {
        [self updateLayers];
    }
}

- (void)setBounds:(CGRect)bounds
{
    // We only need to update our layers if the _size_ of this view
    // changes since the contents of the layers are in local coordinates.
    BOOL didChangeSize = !CGSizeEqualToSize(self.bounds.size, bounds.size);

    [super setBounds:bounds];

    if (didChangeSize) {
        [self updateLayers];
    }
}

- (void)setFillColor:(nullable UIColor *)fillColor
{
    OWSAssertIsOnMainThread();

    _fillColor = fillColor;
    _fillGradientColors = nil;

    [self updateLayers];
}

- (void)setFillGradientColors:(nullable NSArray<UIColor *> *)fillGradientColors
{
    OWSAssertIsOnMainThread();

    _fillColor = nil;
    _fillGradientColors = fillGradientColors;

    [self updateLayers];
}

- (void)setStrokeColor:(nullable UIColor *)strokeColor
{
    _strokeColor = strokeColor;

    [self updateLayers];
}

- (void)setStrokeThickness:(CGFloat)strokeThickness
{
    _strokeThickness = strokeThickness;

    [self updateLayers];
}

- (void)setSharpCorners:(OWSDirectionalRectCorner)sharpCorners
{
    _sharpCorners = sharpCorners;

    [self updateLayers];
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    [self ensureSubviewLayout];
}

- (void)ensureSubviewLayout
{
    if (self.ensureSubviewsFillBounds) {
        for (UIView *subview in self.subviews) {
            subview.frame = self.bounds;
        }
    }
}

- (void)updateLayers
{
    if (!self.maskLayer) {
        return;
    }
    if (!self.shapeLayer) {
        return;
    }
    if (!self.gradientLayer) {
        return;
    }

    UIBezierPath *bezierPath = [self maskPath];

    self.shapeLayer.fillColor = self.fillColor.CGColor;
    self.shapeLayer.strokeColor = self.strokeColor.CGColor;
    self.shapeLayer.lineWidth = self.strokeThickness;
    self.shapeLayer.path = bezierPath.CGPath;
    self.shapeLayer.hidden = (self.fillColor == nil) && (self.strokeColor == nil);

    NSArray *_Nullable fillGradientCGColors = self.fillGradientCGColors;
    self.gradientLayer.colors = fillGradientCGColors;
    self.gradientLayer.hidden = fillGradientCGColors.count < 1;
    // Currently this view only supports linear (or axial) gradients
    // from the top-left to bottom-right.
    self.gradientLayer.startPoint = CGPointMake(0, 0);
    self.gradientLayer.endPoint = CGPointMake(1, 1);
    self.gradientLayer.frame = self.bounds;

    self.maskLayer.path = bezierPath.CGPath;

    BOOL noSharpCorners = (self.sharpCorners == 0);
    BOOL allSharpCorners
        = (self.sharpCorners & OWSDirectionalRectCornerAllCorners) == OWSDirectionalRectCornerAllCorners;

    if (noSharpCorners || allSharpCorners) {
        // Although we have a bubble bezier path, it's just a simple rounded rect
        // It's more performant to use the CA corner mask property than a layer mask
        CGFloat sharpRadius = kOWSMessageCellCornerRadius_Small;
        CGFloat wideRadius = kOWSMessageCellCornerRadius_Large;

        self.layer.cornerRadius = (self.sharpCorners == 0) ? wideRadius : sharpRadius;
        self.layer.mask = nil;
    } else {
        self.layer.cornerRadius = 0;
        self.layer.mask = self.maskLayer;
    }

    [self ensureSubviewLayout];
}

- (nullable NSArray *)fillGradientCGColors
{
    if (self.fillGradientColors.count < 1) {
        return nil;
    }
    NSMutableArray *result = [NSMutableArray new];
    for (UIColor *color in self.fillGradientColors) {
        [result addObject:(id)color.CGColor];
    }
    return result;
}

- (UIView *)bubbleReferenceView
{
    return self;
}

- (UIBezierPath *)maskPath
{
    return [self.class maskPathForSize:self.bounds.size sharpCorners:self.sharpCorners];
}

+ (UIBezierPath *)maskPathForSize:(CGSize)size sharpCorners:(OWSDirectionalRectCorner)sharpCorners
{
    CGRect bubbleRect = CGRectZero;
    bubbleRect.size = size;
    UIRectCorner uiSharpCorners = [UIView uiRectCornerForOWSDirectionalRectCorner:sharpCorners];
    return [UIView roundedBezierRectWithRect:bubbleRect
                                sharpCorners:uiSharpCorners
                           sharpCornerRadius:kOWSMessageCellCornerRadius_Small
                            wideCornerRadius:kOWSMessageCellCornerRadius_Large];
}

- (void)updateConstraints
{
    [super updateConstraints];

    [self deactivateAllConstraints];
}

// MARK: - CALayerDelegate

- (nullable id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event
{
    // Disable all implicit CALayer animations.
    return [NSNull new];
}

@end

NS_ASSUME_NONNULL_END
