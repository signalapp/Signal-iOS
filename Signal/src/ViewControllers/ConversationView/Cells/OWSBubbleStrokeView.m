//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBubbleStrokeView.h"
#import "OWSBubbleView.h"
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSBubbleStrokeView ()

@property (nonatomic) CAShapeLayer *shapeLayer;

@end

#pragma mark -

@implementation OWSBubbleStrokeView

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.opaque = NO;
    self.backgroundColor = [UIColor clearColor];

    return self;
}

- (void)setStrokeColor:(UIColor *)strokeColor
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
    BOOL didChange = !CGSizeEqualToSize(self.frame.size, frame.size);

    [super setFrame:frame];

    if (didChange || !self.shapeLayer) {
        [self updateLayers];
    }
}

- (void)setBounds:(CGRect)bounds
{
    BOOL didChange = !CGSizeEqualToSize(self.bounds.size, bounds.size);

    [super setBounds:bounds];

    if (didChange || !self.shapeLayer) {
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
        self.shapeLayer = [CAShapeLayer new];
        [self.layer addSublayer:self.shapeLayer];
    }

    // Don't fill the shape layer; we just want a stroke around the border.
    self.shapeLayer.fillColor = [UIColor clearColor].CGColor;

    self.clipsToBounds = YES;

    if (!self.bubbleView) {
        return;
    }

    self.shapeLayer.strokeColor = self.strokeColor.CGColor;
    self.shapeLayer.lineWidth = self.strokeThickness;
    self.shapeLayer.zPosition = 100.f;

    UIBezierPath *bezierPath = [UIBezierPath new];

    UIBezierPath *boundsBezierPath = [UIBezierPath bezierPathWithRect:self.bounds];
    [bezierPath appendPath:boundsBezierPath];

    UIBezierPath *bubbleBezierPath = [self.bubbleView maskPath];
    // We need to convert between coordinate systems using layers, not views.
    CGPoint bubbleOffset = [self.layer convertPoint:CGPointZero fromLayer:self.bubbleView.layer];
    CGAffineTransform transform = CGAffineTransformMakeTranslation(bubbleOffset.x, bubbleOffset.y);
    [bubbleBezierPath applyTransform:transform];
    [bezierPath appendPath:bubbleBezierPath];

    self.shapeLayer.path = bezierPath.CGPath;
}

@end

NS_ASSUME_NONNULL_END
