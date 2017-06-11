//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

typedef void (^ConfigureShapeLayerBlock)(CAShapeLayer *layer, CGRect bounds);

NS_ASSUME_NONNULL_BEGIN

@interface OWSBezierPathView : UIView

// Configure the view with this method if it uses a single Bezier path.
- (void)setConfigureShapeLayerBlock:(ConfigureShapeLayerBlock)configureShapeLayerBlock;

// Configure the view with this method if it uses multiple Bezier paths.
//
// Paths will be rendered in back-to-front order.
- (void)setConfigureShapeLayerBlocks:(NSArray<ConfigureShapeLayerBlock> *)configureShapeLayerBlocks;

// This method forces the view to reconstruct its layer content.  It shouldn't
// be necessary to call this unless the ConfigureShapeLayerBlocks depend on external
// state which has changed.
- (void)updateLayers;

@end

NS_ASSUME_NONNULL_END
