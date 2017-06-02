//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <JSQMessagesViewController/JSQMessagesCollectionViewCell.h>
#import <UIKit/UIKit.h>

@class TSInteraction;

@interface OWSSystemMessageCell : JSQMessagesCollectionViewCell

@property (nonatomic) TSInteraction *interaction;

- (void)configure;

+ (CGSize)cellSizeForInteraction:(TSInteraction *)interaction collectionViewWidth:(CGFloat)collectionViewWidth;

@end
