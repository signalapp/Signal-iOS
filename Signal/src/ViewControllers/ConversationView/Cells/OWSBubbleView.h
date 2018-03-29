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

@class OWSBubbleStrokeView;

@interface OWSBubbleView : UIView

@property (nonatomic, weak, nullable) OWSBubbleStrokeView *bubbleStrokeView;

@property (nonatomic) BOOL isOutgoing;
@property (nonatomic) BOOL hideTail;

@property (nonatomic, nullable) UIColor *bubbleColor;

- (UIBezierPath *)maskPath;

@end

NS_ASSUME_NONNULL_END
