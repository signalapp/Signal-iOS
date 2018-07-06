//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBubbleShapeView.h"
#import "OWSBubbleView.h"
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, OWSBubbleShapeViewMode) {
    // For stroking or filling.
    OWSBubbleShapeViewMode_Draw,
    OWSBubbleShapeViewMode_Shadow,
    OWSBubbleShapeViewMode_Clip,
};

@interface OWSBubbleShapeView ()

@property (nonatomic) OWSBubbleShapeViewMode mode;

@property (nonatomic) CAShapeLayer *shapeLayer;
@property (nonatomic) CAShapeLayer *maskLayer;

@property (nonatomic, weak) OWSBubbleView *bubbleView;

@end

#pragma mark -

@implementation OWSBubbleShapeView

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.mode = OWSBubbleShapeViewMode_Draw;
    self.opaque = NO;
    self.backgroundColor = [UIColor clearColor];
    self.layoutMargins = UIEdgeInsetsZero;

    self.shapeLayer = [CAShapeLayer new];
    [self.layer addSublayer:self.shapeLayer];

    self.maskLayer = [CAShapeLayer new];

    return self;
}

+ (OWSBubbleShapeView *)bubbleDrawView
{
    OWSBubbleShapeView *instance = [OWSBubbleShapeView new];
    instance.mode = OWSBubbleShapeViewMode_Draw;
    return instance;
}

+ (OWSBubbleShapeView *)bubbleShadowView
{
    OWSBubbleShapeView *instance = [OWSBubbleShapeView new];
    instance.mode = OWSBubbleShapeViewMode_Shadow;
    return instance;
}

+ (OWSBubbleShapeView *)bubbleClipView
{
    OWSBubbleShapeView *instance = [OWSBubbleShapeView new];
    instance.mode = OWSBubbleShapeViewMode_Clip;
    return instance;
}

- (void)setFillColor:(nullable UIColor *)fillColor
{
    _fillColor = fillColor;

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

- (void)setFrame:(CGRect)frame
{
    BOOL didChange = !CGRectEqualToRect(self.frame, frame);

    [super setFrame:frame];

    if (didChange) {
        [self updateLayers];
    }
}

- (void)setBounds:(CGRect)bounds
{
    BOOL didChange = !CGRectEqualToRect(self.bounds, bounds);

    [super setBounds:bounds];

    if (didChange) {
        [self updateLayers];
    }
}

- (void)setCenter:(CGPoint)center
{
    [super setCenter:center];

    [self updateLayers];
}

- (void)updateLayers
{
    if (!self.shapeLayer) {
        return;
    }

    if (!self.bubbleView) {
        return;
    }

    // Prevent the layer from animating changes.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    UIBezierPath *bezierPath = [UIBezierPath new];

    // Add the bubble view's path to the local path.
    UIBezierPath *bubbleBezierPath = [self.bubbleView maskPath];
    // We need to convert between coordinate systems using layers, not views.
    CGPoint bubbleOffset = [self.layer convertPoint:CGPointZero fromLayer:self.bubbleView.layer];
    CGAffineTransform transform = CGAffineTransformMakeTranslation(bubbleOffset.x, bubbleOffset.y);
    [bubbleBezierPath applyTransform:transform];
    [bezierPath appendPath:bubbleBezierPath];

    switch (self.mode) {
        case OWSBubbleShapeViewMode_Draw: {
            UIBezierPath *boundsBezierPath = [UIBezierPath bezierPathWithRect:self.bounds];
            [bezierPath appendPath:boundsBezierPath];

            self.clipsToBounds = YES;

            if (self.strokeColor) {
                self.shapeLayer.strokeColor = self.strokeColor.CGColor;
                self.shapeLayer.lineWidth = self.strokeThickness;
                self.shapeLayer.zPosition = 100.f;
            } else {
                self.shapeLayer.strokeColor = nil;
                self.shapeLayer.lineWidth = 0.f;
            }
            if (self.fillColor) {
                self.shapeLayer.fillColor = self.fillColor.CGColor;
            } else {
                self.shapeLayer.fillColor = nil;
            }

            self.shapeLayer.path = bezierPath.CGPath;

            break;
        }
        case OWSBubbleShapeViewMode_Shadow:
            self.clipsToBounds = NO;

            if (self.fillColor) {
                self.shapeLayer.fillColor = self.fillColor.CGColor;
            } else {
                self.shapeLayer.fillColor = nil;
            }

            self.shapeLayer.path = bezierPath.CGPath;
            self.shapeLayer.frame = self.bounds;
            self.shapeLayer.masksToBounds = YES;

            break;
        case OWSBubbleShapeViewMode_Clip:
            self.maskLayer.path = bezierPath.CGPath;
            self.layer.mask = self.maskLayer;
            break;
    }

    [CATransaction commit];
}

+ (UIBezierPath *)roundedBezierRectWithBubbleTop:(CGFloat)bubbleTop
                                      bubbleLeft:(CGFloat)bubbleLeft
                                    bubbleBottom:(CGFloat)bubbleBottom
                                     bubbleRight:(CGFloat)bubbleRight
                               sharpCornerRadius:(CGFloat)sharpCornerRadius
                                wideCornerRadius:(CGFloat)wideCornerRadius
                                    sharpCorners:(UIRectCorner)sharpCorners
{
    UIBezierPath *bezierPath = [UIBezierPath new];

    const CGFloat topLeftRounding = (sharpCorners & UIRectCornerTopLeft) ? sharpCornerRadius : wideCornerRadius;
    const CGFloat topRightRounding = (sharpCorners & UIRectCornerTopRight) ? sharpCornerRadius : wideCornerRadius;

    const CGFloat bottomRightRounding = (sharpCorners & UIRectCornerBottomRight) ? sharpCornerRadius : wideCornerRadius;
    const CGFloat bottomLeftRounding = (sharpCorners & UIRectCornerBottomLeft) ? sharpCornerRadius : wideCornerRadius;

    const CGFloat topAngle = 3.0f * M_PI_2;
    const CGFloat rightAngle = 0.0f;
    const CGFloat bottomAngle = M_PI_2;
    const CGFloat leftAngle = M_PI;

    // starting just to the right of the top left corner and working clockwise
    [bezierPath moveToPoint:CGPointMake(bubbleLeft + topLeftRounding, bubbleTop)];

    // top right corner
    [bezierPath addArcWithCenter:CGPointMake(bubbleRight - topRightRounding, bubbleTop + topRightRounding)
                          radius:topRightRounding
                      startAngle:topAngle
                        endAngle:rightAngle
                       clockwise:true];

    // bottom right corner
    [bezierPath addArcWithCenter:CGPointMake(bubbleRight - bottomRightRounding, bubbleBottom - bottomRightRounding)
                          radius:bottomRightRounding
                      startAngle:rightAngle
                        endAngle:bottomAngle
                       clockwise:true];

    // bottom left corner
    [bezierPath addArcWithCenter:CGPointMake(bubbleLeft + bottomLeftRounding, bubbleBottom - bottomLeftRounding)
                          radius:bottomLeftRounding
                      startAngle:bottomAngle
                        endAngle:leftAngle
                       clockwise:true];

    // top left corner
    [bezierPath addArcWithCenter:CGPointMake(bubbleLeft + topLeftRounding, bubbleTop + topLeftRounding)
                          radius:topLeftRounding
                      startAngle:leftAngle
                        endAngle:topAngle
                       clockwise:true];
    return bezierPath;
}

@end

NS_ASSUME_NONNULL_END
