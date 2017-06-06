//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <JSQMessagesViewController/JSQMessagesCollectionViewCell.h>
#import <UIKit/UIKit.h>

@class TSInteraction;

@interface OWSSystemMessageCell : JSQMessagesCollectionViewCell

@property (nonatomic, nullable, readonly) TSInteraction *interaction;

- (void)configureWithInteraction:(TSInteraction *)interaction;

+ (CGSize)cellSizeForInteraction:(TSInteraction *)interaction collectionViewWidth:(CGFloat)collectionViewWidth;

@end
