//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "ConversationCollectionView.h"
#import "Signal-Swift.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

@implementation ConversationCollectionView

- (void)setFrame:(CGRect)frame
{
    if (frame.size.width == 0 || frame.size.height == 0) {
        // Ignore iOS Auto Layout's tendency to temporarily zero out the
        // frame of this view during the layout process.
        //
        // The conversation view has an invariant that the collection view
        // should always have a "reasonable" (correct width, non-zero height)
        // size.  This lets us manipulate scroll state at all times, especially
        // before the view has been presented for the first time.  This
        // invariant also saves us from needing all sorts of ugly and incomplete
        // hacks in the conversation view's code.
        return;
    }
    CGSize oldSize = self.frame.size;
    CGSize newSize = frame.size;
    BOOL isChanging = !CGSizeEqualToSize(oldSize, newSize);
    if (isChanging) {
        [self.layoutDelegate collectionViewWillChangeSizeFrom:oldSize to:newSize];
    }
    [super setFrame:frame];
    if (isChanging) {
        [self.layoutDelegate collectionViewDidChangeSizeFrom:oldSize to:newSize];
    }
}

- (void)setBounds:(CGRect)bounds
{
    if (bounds.size.width == 0 || bounds.size.height == 0) {
        // Ignore iOS Auto Layout's tendency to temporarily zero out the
        // frame of this view during the layout process.
        //
        // The conversation view has an invariant that the collection view
        // should always have a "reasonable" (correct width, non-zero height)
        // size.  This lets us manipulate scroll state at all times, especially
        // before the view has been presented for the first time.  This
        // invariant also saves us from needing all sorts of ugly and incomplete
        // hacks in the conversation view's code.
        return;
    }
    CGSize oldSize = self.bounds.size;
    CGSize newSize = bounds.size;
    BOOL isChanging = !CGSizeEqualToSize(oldSize, newSize);
    if (isChanging) {
        [self.layoutDelegate collectionViewWillChangeSizeFrom:oldSize to:newSize];
    }
    [super setBounds:bounds];
    if (isChanging) {
        [self.layoutDelegate collectionViewDidChangeSizeFrom:oldSize to:newSize];
    }
}

- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated
{
    if (animated) {
        [self.layoutDelegate collectionViewWillAnimate];
    }

    [super setContentOffset:contentOffset animated:animated];
}

- (void)setContentOffset:(CGPoint)contentOffset
{
    if (self.contentSize.height < 1 && contentOffset.y <= 0) {
        // [UIScrollView _adjustContentOffsetIfNecessary] resets the content
        // offset to zero under a number of undocumented conditions.  We don't
        // want this behavior; we want fine-grained control over the default
        // scroll state of the message view.
        //
        // [UIScrollView _adjustContentOffsetIfNecessary] is called in
        // response to many different events; trying to prevent them all is
        // whack-a-mole.
        //
        // It's not safe to override [UIScrollView _adjustContentOffsetIfNecessary],
        // since its a private API.
        //
        // We can avoid the issue by simply ignoring attempt to reset the content
        // offset to zero before the collection view has determined its content size.
        return;
    }

    [super setContentOffset:contentOffset];
}

- (void)scrollRectToVisible:(CGRect)rect animated:(BOOL)animated
{
    if (animated) {
        [self.layoutDelegate collectionViewWillAnimate];
    }

    [super scrollRectToVisible:rect animated:animated];
}

- (void)cvc_reloadDataWithAnimated:(BOOL)animated cvc:(ConversationViewController *)cvc
{
    @try {
        if (animated) {
            [cvc.layout willReloadData];
            [UIView performWithoutAnimation:^{ [super reloadData]; }];
            [cvc.layout invalidateLayout];
            [cvc.layout didReloadData];
        } else {
            [cvc.layout willReloadData];
            [super reloadData];
            [cvc.layout invalidateLayout];
            [cvc.layout didReloadData];
        }
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

- (void)cvc_performBatchUpdates:(CVCPerformBatchUpdatesBlock)batchUpdates
                     completion:(CVCPerformBatchUpdatesCompletion)completion
                        failure:(CVCPerformBatchUpdatesFailure)failure
                       animated:(BOOL)animated
          scrollContinuityToken:(nullable CVScrollContinuityToken *)scrollContinuityToken
                            cvc:(ConversationViewController *)cvc
{
    @try {
        void (^updateBlock)(void) = ^{
            ConversationViewLayout *layout = cvc.layout;
            [layout willPerformBatchUpdatesWithScrollContinuityToken:scrollContinuityToken];
            [cvc.collectionView
                performBatchUpdates:^{ batchUpdates(); }
                completion:^(BOOL finished) {
                    [layout didCompleteBatchUpdates];

                    completion(finished);
                }];
            [layout didPerformBatchUpdatesWithScrollContinuityToken:scrollContinuityToken];

            [BenchManager completeEventWithEventId:@"message-send"];
        };

        if (animated) {
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

        failure();

        @throw exception;
    }
}

@end

NS_ASSUME_NONNULL_END
