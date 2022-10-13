//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

typedef void (^ConfigureShapeLayerBlock)(CAShapeLayer *_Nonnull layer, CGRect bounds);

NS_ASSUME_NONNULL_BEGIN

@interface OWSBezierPathView : UIView

// Configure the view with this method if it uses a single Bezier path.
@property (nonatomic) ConfigureShapeLayerBlock configureShapeLayerBlock;

// Configure the view with this method if it uses multiple Bezier paths.
//
// Paths will be rendered in back-to-front order.
@property (nonatomic) NSArray<ConfigureShapeLayerBlock> *configureShapeLayerBlocks;

// This method forces the view to reconstruct its layer content.  It shouldn't
// be necessary to call this unless the ConfigureShapeLayerBlocks depend on external
// state which has changed.
- (void)updateLayers;

@end

NS_ASSUME_NONNULL_END
