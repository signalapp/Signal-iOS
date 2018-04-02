//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSBubbleView;

@interface OWSBubbleStrokeView : UIView

@property (nonatomic, weak) OWSBubbleView *bubbleView;

@property (nonatomic) UIColor *strokeColor;
@property (nonatomic) CGFloat strokeThickness;

- (void)updateLayers;

@end

NS_ASSUME_NONNULL_END
