//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewCell.h"

@class OWSMessageBubbleView;
@class OWSMessageStickerView;
@class OWSMessageView;
@class OWSMessageViewOnceView;

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageCell : ConversationViewCell <SelectableConversationCell>

@property (nonatomic, readonly) OWSMessageBubbleView *messageBubbleView;
@property (nonatomic, readonly) OWSMessageStickerView *messageStickerView;
@property (nonatomic, readonly) OWSMessageViewOnceView *messageViewOnceView;
@property (nonatomic, readonly) OWSMessageView *messageView;

@property (nonatomic, readonly) UITapGestureRecognizer *messageViewTapGestureRecognizer;
@property (nonatomic, readonly) UITapGestureRecognizer *contentViewTapGestureRecognizer;
@property (nonatomic, readonly) UIPanGestureRecognizer *panGestureRecognizer;
@property (nonatomic, readonly) UILongPressGestureRecognizer *longPressGestureRecognizer;

- (instancetype)init;
- (nullable instancetype)initWithCoder:(NSCoder *)coder;
- (instancetype)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
