//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@protocol ConversationCollectionViewDelegate <NSObject>

- (void)collectionViewWillChangeSizeFrom:(CGSize)oldSize to:(CGSize)newSize;
- (void)collectionViewDidChangeSizeFrom:(CGSize)oldSize to:(CGSize)newSize;

@end

#pragma mark -

@interface ConversationCollectionView : UICollectionView

@property (weak, nonatomic) id<ConversationCollectionViewDelegate> layoutDelegate;

@end

NS_ASSUME_NONNULL_END
