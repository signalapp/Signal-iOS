//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "ConversationCollectionView.h"
#import "Signal-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@implementation ConversationCollectionView

- (void)setFrame:(CGRect)frame
{
    OWSAssertIsOnMainThread();

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
    OWSAssertIsOnMainThread();

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
    OWSAssertIsOnMainThread();

    if (animated) {
        [self.layoutDelegate collectionViewWillAnimate];
    }

    [super setContentOffset:contentOffset animated:animated];
}

- (void)setContentOffset:(CGPoint)contentOffset
{
    OWSAssertIsOnMainThread();

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

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return
        [self.layoutDelegate collectionViewShouldRecognizeSimultaneouslyWithGestureRecognizer:otherGestureRecognizer];
}

@end

NS_ASSUME_NONNULL_END
