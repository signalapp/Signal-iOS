//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBezierPathView.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

@implementation OWSBezierPathView

- (id)init
{
    self = [super init];
    if (self) {
        [self initCommon];
    }

    return self;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self initCommon];
    }
    return self;
}

- (void)initCommon
{
    self.opaque = NO;
    self.userInteractionEnabled = NO;
    self.backgroundColor = [UIColor clearColor];
}

- (void)setFrame:(CGRect)frame
{
    BOOL didChangeSize = !CGSizeEqualToSize(frame.size, self.frame.size);

    [super setFrame:frame];

    if (didChangeSize) {
        [self updateLayers];
    }
}

- (void)setBounds:(CGRect)bounds
{
    BOOL didChangeSize = !CGSizeEqualToSize(bounds.size, self.bounds.size);

    [super setBounds:bounds];

    if (didChangeSize) {
        [self updateLayers];
    }
}

- (void)setConfigureShapeLayerBlock:(ConfigureShapeLayerBlock)configureShapeLayerBlock
{
    OWSAssertDebug(configureShapeLayerBlock);

    [self setConfigureShapeLayerBlocks:@[ configureShapeLayerBlock ]];
}

- (void)setConfigureShapeLayerBlocks:(NSArray<ConfigureShapeLayerBlock> *)configureShapeLayerBlocks
{
    OWSAssertDebug(configureShapeLayerBlocks.count > 0);

    _configureShapeLayerBlocks = configureShapeLayerBlocks;

    [self updateLayers];
}

- (void)updateLayers
{
    if (self.bounds.size.width <= 0.f || self.bounds.size.height <= 0.f) {
        return;
    }

    for (CALayer *layer in self.layer.sublayers) {
        [layer removeFromSuperlayer];
    }

    // Prevent the shape layer from animating changes.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    for (ConfigureShapeLayerBlock configureShapeLayerBlock in self.configureShapeLayerBlocks) {
        CAShapeLayer *shapeLayer = [CAShapeLayer new];
        configureShapeLayerBlock(shapeLayer, self.bounds);
        [self.layer addSublayer:shapeLayer];
    }

    [CATransaction commit];

    [self setNeedsDisplay];
}

@end

NS_ASSUME_NONNULL_END
