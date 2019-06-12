//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewCell.h"

@class OWSMessageBubbleView;
@class OWSMessageStickerView;

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageCell : ConversationViewCell

@property (nonatomic, readonly) OWSMessageBubbleView *messageBubbleView;
@property (nonatomic, readonly) OWSMessageStickerView *messageStickerView;
@property (nonatomic, readonly) UIPanGestureRecognizer *panGestureRecognizer;

+ (NSString *)cellReuseIdentifier;

@end

NS_ASSUME_NONNULL_END
