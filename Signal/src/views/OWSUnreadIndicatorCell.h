//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <JSQMessagesViewController/JSQMessagesCollectionViewCell.h>
#import <UIKit/UIKit.h>

@class TSUnreadIndicatorInteraction;

@interface OWSUnreadIndicatorCell : JSQMessagesCollectionViewCell

@property (nonatomic) TSUnreadIndicatorInteraction *interaction;

- (void)configure;

+ (CGSize)cellSizeForInteraction:(TSUnreadIndicatorInteraction *)interaction
             collectionViewWidth:(CGFloat)collectionViewWidth;

@end
