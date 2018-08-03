//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBubbleShapeView.h"
#import "OWSBubbleView.h"
#import <RelayMessaging/UIView+OWS.h>

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

@end

NS_ASSUME_NONNULL_END
