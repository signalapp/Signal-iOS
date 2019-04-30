//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ContactShareViewModel;
@class ConversationStyle;
@class TSAttachmentStream;
@class TSOutgoingMessage;

@protocol ConversationViewItem;
@protocol OWSMessageStickerViewDelegate

@end

#pragma mark -

@interface OWSMessageStickerView : UIView

@property (nonatomic, nullable) id<ConversationViewItem> viewItem;

@property (nonatomic) ConversationStyle *conversationStyle;

@property (nonatomic) NSCache *cellMediaCache;

@property (nonatomic, weak) id<OWSMessageStickerViewDelegate> delegate;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (void)configureViews;

- (void)loadContent;
- (void)unloadContent;

- (CGSize)measureSize;

- (void)prepareForReuse;

#pragma mark - Gestures

// This only needs to be called when we use the cell _outside_ the context
// of a conversation view message cell.
- (void)addTapGestureHandler;

- (void)handleTapGesture:(UITapGestureRecognizer *)sender;

@end

NS_ASSUME_NONNULL_END
