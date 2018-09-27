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
    OWSBubbleShapeViewMode_InnerShadow,
};

@interface OWSBubbleShapeView ()

@property (nonatomic) OWSBubbleShapeViewMode mode;

@property (nonatomic) CAShapeLayer *shapeLayer;
@property (nonatomic) CAShapeLayer *maskLayer;

@property (nonatomic, weak) OWSBubbleView *bubbleView;

@end

#pragma mark -

@implementation OWSBubbleShapeView

- (void)configure
{
    self.mode = OWSBubbleShapeViewMode_Draw;
    self.opaque = NO;
    self.backgroundColor = [UIColor clearColor];
    self.layoutMargins = UIEdgeInsetsZero;

    self.shapeLayer = [CAShapeLayer new];
    [self.layer addSublayer:self.shapeLayer];

    self.maskLayer = [CAShapeLayer new];
}


- (instancetype)initDraw
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.mode = OWSBubbleShapeViewMode_Draw;

    [self configure];

    return self;
}

- (instancetype)initShadow
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.mode = OWSBubbleShapeViewMode_Shadow;

    [self configure];

    return self;
}

- (instancetype)initClip
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.mode = OWSBubbleShapeViewMode_Clip;

    [self configure];

    return self;
}

- (instancetype)initInnerShadowWithColor:(UIColor *)color radius:(CGFloat)radius opacity:(float)opacity
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.mode = OWSBubbleShapeViewMode_InnerShadow;
    _innerShadowColor = color;
    _innerShadowRadius = radius;
    _innerShadowOpacity = opacity;

    [self configure];
    [self updateLayers];

    return self;
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

- (void)setInnerShadowColor:(nullable UIColor *)innerShadowColor
{
    _innerShadowColor = innerShadowColor;

    [self updateLayers];
}

- (void)setInnerShadowRadius:(CGFloat)innerShadowRadius
{
    _innerShadowRadius = innerShadowRadius;

    [self updateLayers];
}

- (void)setInnerShadowOpacity:(float)innerShadowOpacity
{
    _innerShadowOpacity = innerShadowOpacity;

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
        case OWSBubbleShapeViewMode_InnerShadow: {
            self.maskLayer.path = bezierPath.CGPath;
            self.layer.mask = self.maskLayer;

            // Inner shadow.
            // This should usually not be visible; it is used to distinguish
            // profile pics from the background if they are similar.
            self.shapeLayer.frame = self.bounds;
            self.shapeLayer.masksToBounds = YES;
            CGRect shadowBounds = self.bounds;
            UIBezierPath *shadowPath = [bezierPath copy];
            // This can be any value large enough to cast a sufficiently large shadow.
            CGFloat shadowInset = -(self.innerShadowRadius * 4.f);
            [shadowPath
                appendPath:[UIBezierPath bezierPathWithRect:CGRectInset(shadowBounds, shadowInset, shadowInset)]];
            // This can be any color since the fill should be clipped.
            self.shapeLayer.fillColor = UIColor.blackColor.CGColor;
            self.shapeLayer.path = shadowPath.CGPath;
            self.shapeLayer.fillRule = kCAFillRuleEvenOdd;
            self.shapeLayer.shadowColor = self.innerShadowColor.CGColor;
            self.shapeLayer.shadowRadius = self.innerShadowRadius;
            self.shapeLayer.shadowOpacity = self.innerShadowOpacity;
            self.shapeLayer.shadowOffset = CGSizeZero;

            break;
        }
    }

    [CATransaction commit];
}

@end

NS_ASSUME_NONNULL_END
