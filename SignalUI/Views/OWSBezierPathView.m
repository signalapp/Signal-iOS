//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSBezierPathView.h"
#import <SignalUI/SignalUI-Swift.h>

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
    OWSAssertDebug(self.layer.delegate == self);
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

    for (ConfigureShapeLayerBlock configureShapeLayerBlock in self.configureShapeLayerBlocks) {
        CAShapeLayer *shapeLayer = [CAShapeLayer new];
        [shapeLayer disableAnimationsWithDelegate];
        configureShapeLayerBlock(shapeLayer, self.bounds);
        [self.layer addSublayer:shapeLayer];
    }

    [self setNeedsDisplay];
}

// MARK: - CALayerDelegate

- (nullable id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event
{
    // Disable all implicit CALayer animations.
    return [NSNull new];
}

@end

NS_ASSUME_NONNULL_END
