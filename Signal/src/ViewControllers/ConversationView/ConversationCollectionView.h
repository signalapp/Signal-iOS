//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ConversationCollectionViewDelegate <NSObject>

- (void)collectionViewWillChangeSizeFrom:(CGSize)oldSize to:(CGSize)newSize;
- (void)collectionViewDidChangeSizeFrom:(CGSize)oldSize to:(CGSize)newSize;
- (void)collectionViewWillAnimate;
- (BOOL)collectionViewShouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer;

@end

#pragma mark -

@interface ConversationCollectionView : UICollectionView

@property (weak, nonatomic) id<ConversationCollectionViewDelegate> layoutDelegate;

@end

NS_ASSUME_NONNULL_END
