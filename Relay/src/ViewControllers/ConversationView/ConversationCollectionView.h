//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@protocol ConversationCollectionViewDelegate <NSObject>

- (void)collectionViewWillChangeLayout;
- (void)collectionViewDidChangeLayout;

@end

#pragma mark -

@interface ConversationCollectionView : UICollectionView

@property (weak, nonatomic) id<ConversationCollectionViewDelegate> layoutDelegate;

@end

NS_ASSUME_NONNULL_END
