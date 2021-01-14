//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ConversationCollectionView.h"

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

    if ([self shouldSkipAdjustmentDueToLoadingMoreWhileOverscrolledWithProposedContentOffset:contentOffset]) {
        OWSLogInfo(@"Ignoring contentOffset");
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

- (BOOL)shouldSkipAdjustmentDueToLoadingMoreWhileOverscrolledWithProposedContentOffset:(CGPoint)proposedContentOffset
{
    // Fixes situation where the user is farther back in their conversation history than they expect
    // when overscrolling while loading more.
    //
    // Our scrollView supports bounce - you can overscroll, and once you pick up your finger,
    // it'll animate you back to the bounds of the scroll view content. e.g. if you overscroll
    // the top of the content, UIKit will "bounce" back to the top bound of the content.
    //
    // Generally speaking, this is good UX, conventional for the platform, and something we want
    // to support.
    //
    // However, in the case that we're scrolled to the top and there is more content to load, we
    // can end up in this scenario:
    //
    // - user is overscrolled, and lets go of their finger, then these two things happen concurrently:
    //   1. app loads more message cells and adjusts content offset so as to maintain the previous conversation
    //      context
    //   2. since the user *was* overscrolled at the time they released their finger, iOS completes the "bounce
    //      back" and animates the content to the **new** top of the view port, which is above all the "just loaded"
    //      messages.
    //
    //  Since we've inserted new content at the top, we're no longer actually "over scrolled", so we should avoid
    //  adjusting the content offset back to the (new) top.
    //
    // If you set a breakpoint within this block, you'll see that we repeatedly have a stack frame
    // like this, with a content-offset that reflects the NEW top, rather than the content that was
    // at the OLD top, where we should be.
    //
    //     -[ConversationCollectionView setContentOffset:]
    //     -[UIScrollView _smoothScrollWithUpdateTime:] ()
    //     -[UIScrollView _smoothScrollDisplayLink:] ()
    //     -[DYDisplayLinkInterposer forwardDisplayLinkCallback:] ()
    //     CA::Display::DisplayLink::dispatch_items(unsigned long long, unsigned long long, unsigned long long) ()
    //     display_timer_callback(__CFMachPort*, void*, long, void*) ()
    //     [...]
    //
    CGFloat heightDelta = self.contentOffset.y - proposedContentOffset.y;

    // This number is somewhat arbitrary, but since this is "weird code" we want to limit the
    // set of cirumstances where we apply it.
    //
    // During normal scrolling, contentOffset changes are small.
    if (fabs(heightDelta) < 1000) {
        // If this is only a small change, it probably does not corresond to jumping across
        // a newly loaded page.
        return NO;
    }

    // The top content offset is actually less than 0 due to contentInset/safeArea
    // If the new contentOffset is > 0, this doesn't reflect an attempt to scroll to top.
    BOOL isNearTop = proposedContentOffset.y < 0;
    BOOL isNearBottom = self.contentSize.height - proposedContentOffset.y < self.bounds.size.height;
    if (!(isNearTop || isNearBottom)) {
        // If we're not near the top nor the bottom, then we're not overscrolled and the fix need not apply.
        return NO;
    }

    if (!self.isDecelerating) {
        // When "bouncing back" after overscrolling, isDecelerating will be true. If we're
        // not decelerating, then we weren't overscrolled, and the fix need not apply.
        return NO;
    }

    return YES;
}

@end

NS_ASSUME_NONNULL_END
