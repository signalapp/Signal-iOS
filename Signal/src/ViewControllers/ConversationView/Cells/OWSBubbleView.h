//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat kOWSMessageCellCornerRadius;

extern const CGFloat kBubbleVRounding;
extern const CGFloat kBubbleHRounding;
extern const CGFloat kBubbleThornSideInset;
extern const CGFloat kBubbleThornVInset;
extern const CGFloat kBubbleTextHInset;
extern const CGFloat kBubbleTextVInset;

@interface OWSBubbleView : UIView

@property (nonatomic) BOOL isOutgoing;
@property (nonatomic) BOOL hideTail;

@property (nonatomic) CAShapeLayer *maskLayer;
@property (nonatomic) CAShapeLayer *shapeLayer;

@property (nonatomic, nullable) UIColor *bubbleColor;

@end

NS_ASSUME_NONNULL_END
