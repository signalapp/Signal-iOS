//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <JSQMessagesViewController/JSQMessagesCollectionViewCell.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TSUnreadIndicatorInteraction;

@interface OWSUnreadIndicatorCell : JSQMessagesCollectionViewCell

@property (nonatomic, nullable, readonly) TSUnreadIndicatorInteraction *interaction;

- (void)configureWithInteraction:(TSUnreadIndicatorInteraction *)interaction;

+ (CGSize)cellSizeForInteraction:(TSUnreadIndicatorInteraction *)interaction
             collectionViewWidth:(CGFloat)collectionViewWidth;

@end

NS_ASSUME_NONNULL_END
