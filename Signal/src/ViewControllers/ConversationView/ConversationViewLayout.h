//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ConversationViewLayoutAlignment) {
    ConversationViewLayoutAlignment_Incoming,
    ConversationViewLayoutAlignment_Outgoing,
    ConversationViewLayoutAlignment_FullWidth,
    ConversationViewLayoutAlignment_Center,
};

@protocol ConversationViewLayoutItem <NSObject>

- (CGSize)cellSizeForViewWidth:(int)viewWidth contentWidth:(int)contentWidth;

- (ConversationViewLayoutAlignment)layoutAlignment;

@end

#pragma mark -

@protocol ConversationViewLayoutDelegate <NSObject>

- (NSArray<id<ConversationViewLayoutItem>> *)layoutItems;

@end

#pragma mark -

@interface ConversationViewLayout : UICollectionViewLayout

@property (nonatomic, weak) id<ConversationViewLayoutDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
