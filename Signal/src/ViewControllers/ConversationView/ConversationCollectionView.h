//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

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

#pragma mark -

typedef void (^ObjCTryBlock)(void);
typedef void (^ObjCTryFailureBlock)(void);

#pragma mark -

@interface ObjCTry : NSObject

+ (void)perform:(ObjCTryBlock)tryBlock failureBlock:(ObjCTryFailureBlock)failureBlock label:(NSString *)label;

@end

NS_ASSUME_NONNULL_END
