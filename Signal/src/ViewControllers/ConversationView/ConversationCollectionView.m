//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ConversationCollectionView.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

@implementation ConversationCollectionView

- (void)setFrame:(CGRect)frame
{
    BOOL isChanging = !CGSizeEqualToSize(frame.size, self.frame.size);
    if (isChanging) {
        [self.layoutDelegate collectionViewWillChangeLayout];
    }
    [super setFrame:frame];
    if (isChanging) {
        [self.layoutDelegate collectionViewDidChangeLayout];
    }
}

- (void)setBounds:(CGRect)bounds
{
    BOOL isChanging = !CGSizeEqualToSize(bounds.size, self.bounds.size);
    if (isChanging) {
        [self.layoutDelegate collectionViewWillChangeLayout];
    }
    [super setBounds:bounds];
    if (isChanging) {
        [self.layoutDelegate collectionViewDidChangeLayout];
    }
}

- (void)setContentOffset:(CGPoint)contentOffset
{
    if (self.contentSize.height < 1 && CGPointEqualToPoint(CGPointZero, contentOffset)) {
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

@end

NS_ASSUME_NONNULL_END
