//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <JSQMessagesViewController/JSQMessagesCollectionViewCell.h>
#import <UIKit/UIKit.h>

@class TSUnreadIndicatorInteraction;

@interface OWSUnreadIndicatorCell : JSQMessagesCollectionViewCell

@property (nonatomic, nullable, readonly) TSUnreadIndicatorInteraction *interaction;

- (void)configureWithInteraction:(TSUnreadIndicatorInteraction *)interaction;

+ (CGSize)cellSizeForInteraction:(TSUnreadIndicatorInteraction *)interaction
             collectionViewWidth:(CGFloat)collectionViewWidth;

@end
