//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewController.h"
#import "Signal-Swift.h"

NS_ASSUME_NONNULL_BEGIN

void CVCReloadCollectionViewForReset(ConversationViewController *cvc)
{
    @try {
        [cvc.layout willReloadData];
        [cvc.collectionView reloadData];
        [cvc.layout invalidateLayout];
        [cvc.layout didReloadData];
    } @catch (NSException *exception) {
        OWSLogWarn(@"currentRenderStateDebugDescription: %@", cvc.currentRenderStateDebugDescription);
        OWSCFailDebug(@"exception: %@ of type: %@ with reason: %@, user info: %@.",
                      exception.description,
                      exception.name,
                      exception.reason,
                      exception.userInfo);
        @throw exception;
    }
}

void CVCPerformBatchUpdates(ConversationViewController *cvc,
                            CVCPerformBatchUpdatesBlock batchUpdates,
                            CVCPerformBatchUpdatesCompletion completion,
                            CVCPerformBatchUpdatesFailure logFailureBlock,
                            BOOL shouldAnimateUpdates,
                            BOOL isLoadAdjacent)
{
    @try {
        void (^updateBlock)(void) = ^{
            ConversationViewLayout *layout = cvc.layout;
            [layout willPerformBatchUpdatesWithAnimated:shouldAnimateUpdates
                                         isLoadAdjacent:isLoadAdjacent];
            [cvc.collectionView performBatchUpdates:batchUpdates
                                         completion:^(BOOL finished) {
                [layout didCompleteBatchUpdates];
                
                completion(finished);
            }];
            [layout didPerformBatchUpdatesWithAnimated:shouldAnimateUpdates];
            
            [BenchManager completeEventWithEventId:@"message-send"];
        };
        
        if (shouldAnimateUpdates) {
            updateBlock();
        } else {
            // HACK: We use `UIView.animateWithDuration:0` rather than `UIView.performWithAnimation` to work around a
            // UIKit Crash like:
            //
            //     *** Assertion failure in -[ConversationViewLayout prepareForCollectionViewUpdates:],
            //     /BuildRoot/Library/Caches/com.apple.xbs/Sources/UIKit_Sim/UIKit-3600.7.47/UICollectionViewLayout.m:760
            //     *** Terminating app due to uncaught exception 'NSInternalInconsistencyException', reason: 'While
            //     preparing update a visible view at <NSIndexPath: 0xc000000011c00016> {length = 2, path = 0 - 142}
            //     wasn't found in the current data model and was not in an update animation. This is an internal
            //     error.'
            //
            // I'm unclear if this is a bug in UIKit, or if we're doing something crazy in
            // ConversationViewLayout#prepareLayout. To reproduce, rapidily insert and delete items into the
            // conversation. See `DebugUIMessages#thrashCellsInThread:`
            [UIView animateWithDuration:0.0 animations:updateBlock];
        }
    } @catch (NSException *exception) {
        OWSCFailDebug(@"exception: %@ of type: %@ with reason: %@, user info: %@.",
                     exception.description,
                     exception.name,
                     exception.reason,
                     exception.userInfo);
        
        logFailureBlock();
        
        @throw exception;
    }
}

NS_ASSUME_NONNULL_END
