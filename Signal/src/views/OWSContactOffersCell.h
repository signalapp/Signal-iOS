//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <JSQMessagesViewController/JSQMessagesCollectionViewCell.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSContactOffersInteraction;

@protocol OWSContactOffersCellDelegate <NSObject>

- (void)tappedUnknownContactBlockOfferMessage:(OWSContactOffersInteraction *)interaction;
- (void)tappedAddToContactsOfferMessage:(OWSContactOffersInteraction *)interaction;
- (void)tappedAddToProfileWhitelistOfferMessage:(OWSContactOffersInteraction *)interaction;

@end

#pragma mark -

@interface OWSContactOffersCell : JSQMessagesCollectionViewCell

@property (nonatomic, weak) id<OWSContactOffersCellDelegate> contactOffersCellDelegate;

@property (nonatomic, nullable, readonly) OWSContactOffersInteraction *interaction;

- (void)configureWithInteraction:(OWSContactOffersInteraction *)interaction;

- (CGSize)bubbleSizeForInteraction:(OWSContactOffersInteraction *)interaction
               collectionViewWidth:(CGFloat)collectionViewWidth;

@end

NS_ASSUME_NONNULL_END
