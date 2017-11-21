//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewCell.h"
#import "ConversationViewItem.h"

NS_ASSUME_NONNULL_BEGIN

@implementation ConversationViewCell

- (void)prepareForReuse
{
    [super prepareForReuse];

    self.viewItem = nil;
    self.delegate = nil;
    self.isCellVisible = NO;
    self.contentWidth = 0;
}

- (void)loadForDisplay
{
    OWSFail(@"%@ This method should be overridden.", self.logTag);
}

- (CGSize)cellSizeForViewWidth:(int)viewWidth contentWidth:(int)contentWidth
{
    OWSFail(@"%@ This method should be overridden.", self.logTag);
    return CGSizeZero;
}

- (void)setIsCellVisible:(BOOL)isCellVisible
{
    _isCellVisible = isCellVisible;

    if (isCellVisible) {
        [self forceLayoutImmediately];
    }
}

- (void)setFrame:(CGRect)frame
{
    BOOL didSizeChange = CGSizeEqualToSize(self.frame.size, frame.size);

    [super setFrame:frame];

    if (didSizeChange) {
        [self forceLayoutImmediately];
    }
}

- (void)setBounds:(CGRect)bounds
{
    BOOL didSizeChange = CGSizeEqualToSize(self.bounds.size, bounds.size);

    [super setBounds:bounds];

    if (didSizeChange) {
        [self forceLayoutImmediately];
    }
}

- (void)forceLayoutImmediately
{
    NSArray<UIView *> *descendents = [ConversationViewCell collectSubviewsOfViewDepthFirst:self];
    for (UIView *view in descendents) {
        [view setNeedsLayout];
    }
    for (UIView *view in descendents.reverseObjectEnumerator) {
        [view layoutIfNeeded];
    }
}

+ (NSArray<UIView *> *)collectSubviewsOfViewDepthFirst:(UIView *)view
{
    NSMutableArray<UIView *> *result = [NSMutableArray new];
    for (UIView *subview in view.subviews) {
        [result addObjectsFromArray:[self collectSubviewsOfViewDepthFirst:subview]];
    }
    [result addObject:view];
    return result;
}

@end

NS_ASSUME_NONNULL_END
