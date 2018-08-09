//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
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
    self.conversationStyle = nil;
}

- (void)loadForDisplay
{
    OWS_ABSTRACT_METHOD();
}

- (CGSize)cellSize
{
    OWS_ABSTRACT_METHOD();

    return CGSizeZero;
}

- (void)setIsCellVisible:(BOOL)isCellVisible
{
    _isCellVisible = isCellVisible;

    if (isCellVisible) {
        [self layoutIfNeeded];
    }
}

// For perf reasons, skip the default implementation which is only relevant for self-sizing cells.
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:
    (UICollectionViewLayoutAttributes *)layoutAttributes
{
    return layoutAttributes;
}

@end

NS_ASSUME_NONNULL_END
