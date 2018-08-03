//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ConversationStyle;
@class YapDatabaseConnection;
@class YapDatabaseReadTransaction;

@protocol ConversationViewLayoutItem <NSObject>

- (CGSize)cellSizeWithTransaction:(YapDatabaseReadTransaction *)transaction;

- (CGFloat)vSpacingWithPreviousLayoutItem:(id<ConversationViewLayoutItem>)previousLayoutItem;

@end

#pragma mark -

@protocol ConversationViewLayoutDelegate <NSObject>

- (NSArray<id<ConversationViewLayoutItem>> *)layoutItems;

- (CGFloat)layoutHeaderHeight;

@end

#pragma mark -

// A new lean and efficient layout for conversation view designed to
// handle our edge cases (e.g. full-width unread indicators, etc.).
@interface ConversationViewLayout : UICollectionViewLayout

@property (nonatomic, weak) id<ConversationViewLayoutDelegate> delegate;
@property (nonatomic, readonly) BOOL hasLayout;
@property (nonatomic, readonly) BOOL hasEverHadLayout;
@property (nonatomic, readonly) ConversationStyle *conversationStyle;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithConversationStyle:(ConversationStyle *)conversationStyle
                     uiDatabaseConnection:(YapDatabaseConnection *)uiDatabaseConnection;

@end

NS_ASSUME_NONNULL_END
