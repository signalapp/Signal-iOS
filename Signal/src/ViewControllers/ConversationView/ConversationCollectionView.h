//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class CVScrollContinuityToken;
@class ConversationViewController;

@protocol ConversationCollectionViewDelegate <NSObject>

- (void)collectionViewWillChangeSizeFrom:(CGSize)oldSize to:(CGSize)newSize;
- (void)collectionViewDidChangeSizeFrom:(CGSize)oldSize to:(CGSize)newSize;
- (void)collectionViewWillAnimate;

@end

#pragma mark -

typedef void (^CVCPerformBatchUpdatesBlock)(void);
typedef void (^CVCPerformBatchUpdatesCompletion)(BOOL);
typedef void (^CVCPerformBatchUpdatesFailure)(void);

@interface ConversationCollectionView : UICollectionView

@property (weak, nonatomic) id<ConversationCollectionViewDelegate> layoutDelegate;
@property (nonatomic) BOOL shouldBreakOnContentOffsetChanges;

- (void)reloadData NS_UNAVAILABLE;
- (void)cvc_reloadDataWithAnimated:(BOOL)animated
                               cvc:(ConversationViewController *)cvc NS_SWIFT_NAME(cvc_reloadData(animated:cvc:));

- (void)performBatchUpdates:(void(NS_NOESCAPE ^ _Nullable)(void))updates
                 completion:(void (^_Nullable)(BOOL finished))completion NS_UNAVAILABLE;
- (void)cvc_performBatchUpdates:(CVCPerformBatchUpdatesBlock)batchUpdates
                     completion:(CVCPerformBatchUpdatesCompletion)completion
                        failure:(CVCPerformBatchUpdatesFailure)failure
                       animated:(BOOL)animated
          scrollContinuityToken:(nullable CVScrollContinuityToken *)scrollContinuityToken
                            cvc:(ConversationViewController *)cvc NS_SWIFT_NAME(cvc_performBatchUpdates(_:completion:
                                    failure:
                                    scrollContinuityToken:
                                    cvc:));

@end

NS_ASSUME_NONNULL_END
