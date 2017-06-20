//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <JSQMessagesViewController/JSQMessagesCollectionViewCell.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TSInteraction;
@class OWSSystemMessageCell;

@protocol OWSSystemMessageCellDelegate <NSObject>

- (void)didTapSystemMessageWithInteraction:(TSInteraction *)interaction;
- (void)didLongPressSystemMessageCell:(OWSSystemMessageCell *)systemMessageCell;

@end

#pragma mark -

@interface OWSSystemMessageCell : JSQMessagesCollectionViewCell

@property (nonatomic, weak) id<OWSSystemMessageCellDelegate> systemMessageCellDelegate;

@property (nonatomic, readonly) UILabel *titleLabel;
@property (nonatomic, nullable, readonly) TSInteraction *interaction;

- (void)configureWithInteraction:(TSInteraction *)interaction;

- (CGSize)bubbleSizeForInteraction:(TSInteraction *)interaction collectionViewWidth:(CGFloat)collectionViewWidth;

@end

NS_ASSUME_NONNULL_END
