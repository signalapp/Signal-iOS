//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <JSQMessagesViewController/JSQMessagesCollectionViewCell.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSContactOffersInteraction;

@interface OWSContactOffersCell : JSQMessagesCollectionViewCell

@property (nonatomic, nullable, readonly) OWSContactOffersInteraction *interaction;

- (void)configureWithInteraction:(OWSContactOffersInteraction *)interaction;

- (CGSize)bubbleSizeForInteraction:(OWSContactOffersInteraction *)interaction
               collectionViewWidth:(CGFloat)collectionViewWidth;

@end

NS_ASSUME_NONNULL_END
