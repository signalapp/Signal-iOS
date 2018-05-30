//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewLayout.h"
#import "UIView+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@interface ConversationViewLayout ()

@property (nonatomic) CGSize contentSize;

@property (nonatomic, readonly) NSMutableDictionary<NSNumber *, UICollectionViewLayoutAttributes *> *itemAttributesMap;

// This dirty flag may be redundant with logic in UICollectionViewLayout,
// but it can't hurt and it ensures that we can safely & cheaply call
// prepareLayout from view logic to ensure that we always have a¸valid
// layout without incurring any of the (great) expense of performing an
// unnecessary layout pass.
@property (nonatomic) BOOL hasLayout;
@property (nonatomic) BOOL hasEverHadLayout;

@property (nonatomic) int contentWidth;

@end

#pragma mark -

@implementation ConversationViewLayout

- (instancetype)init
{
    if (self = [super init]) {
        _itemAttributesMap = [NSMutableDictionary new];
    }

    return self;
}

- (void)setHasLayout:(BOOL)hasLayout
{
    _hasLayout = hasLayout;

    if (hasLayout) {
        self.hasEverHadLayout = YES;
    }
}

- (void)invalidateLayout
{
    [super invalidateLayout];

    [self clearState];
}

- (void)invalidateLayoutWithContext:(UICollectionViewLayoutInvalidationContext *)context
{
    [super invalidateLayoutWithContext:context];

    [self clearState];
}

- (void)clearState
{
    self.contentSize = CGSizeZero;
    [self.itemAttributesMap removeAllObjects];
    self.hasLayout = NO;
}

- (void)prepareLayout
{
    [super prepareLayout];

    id<ConversationViewLayoutDelegate> delegate = self.delegate;
    if (!delegate) {
        OWSFail(@"%@ Missing delegate", self.logTag);
        [self clearState];
        return;
    }

    if (self.collectionView.bounds.size.width <= 0.f || self.collectionView.bounds.size.height <= 0.f) {
        OWSFail(
            @"%@ Collection view has invalid size: %@", self.logTag, NSStringFromCGRect(self.collectionView.bounds));
        [self clearState];
        return;
    }

    if (self.hasLayout) {
        return;
    }
    self.hasLayout = YES;

    // TODO: Remove this log statement after we've reduced the invalidation churn.
    DDLogVerbose(@"%@ prepareLayout", self.logTag);

    const int vInset = 8;
    const int hInset = 10;
    const int vSpacing = 5;
    const int viewWidth = (int)floor(self.collectionView.bounds.size.width);
    const int contentWidth = (int)floor(viewWidth - 2 * hInset);
    self.contentWidth = contentWidth;

    NSArray<id<ConversationViewLayoutItem>> *layoutItems = self.delegate.layoutItems;

    CGFloat y = vInset + self.delegate.layoutHeaderHeight;
    CGFloat contentBottom = y;
    BOOL isRTL = self.collectionView.isRTL;

    NSInteger row = 0;
    for (id<ConversationViewLayoutItem> layoutItem in layoutItems) {
        CGSize layoutSize = [layoutItem cellSizeForViewWidth:viewWidth contentWidth:contentWidth];

        layoutSize.width = MIN(viewWidth, floor(layoutSize.width));
        layoutSize.height = floor(layoutSize.height);
        CGRect itemFrame;
        switch (layoutItem.layoutAlignment) {
            case ConversationViewLayoutAlignment_Incoming:
            case ConversationViewLayoutAlignment_Outgoing: {
                BOOL isIncoming = layoutItem.layoutAlignment == ConversationViewLayoutAlignment_Incoming;
                BOOL isLeft = isIncoming ^ isRTL;
                if (isLeft) {
                    itemFrame = CGRectMake(hInset, y, layoutSize.width, layoutSize.height);
                } else {
                    itemFrame
                        = CGRectMake(viewWidth - (hInset + layoutSize.width), y, layoutSize.width, layoutSize.height);
                }
                break;
            }
            case ConversationViewLayoutAlignment_FullWidth:
                itemFrame = CGRectMake(0, y, viewWidth, layoutSize.height);
                break;
            case ConversationViewLayoutAlignment_Center:
                itemFrame = CGRectMake(
                    hInset + round((viewWidth - layoutSize.width) * 0.5f), y, layoutSize.width, layoutSize.height);
                break;
        }

        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        UICollectionViewLayoutAttributes *itemAttributes =
            [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
        itemAttributes.frame = itemFrame;
        self.itemAttributesMap[@(row)] = itemAttributes;

        contentBottom = itemFrame.origin.y + itemFrame.size.height;
        y = contentBottom + vSpacing;
        row++;
    }

    contentBottom += vInset;
    self.contentSize = CGSizeMake(viewWidth, contentBottom);
}

- (nullable NSArray<__kindof UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect
{
    NSMutableArray<UICollectionViewLayoutAttributes *> *result = [NSMutableArray new];
    for (UICollectionViewLayoutAttributes *itemAttributes in self.itemAttributesMap.allValues) {
        if (CGRectIntersectsRect(rect, itemAttributes.frame)) {
            [result addObject:itemAttributes];
        }
    }
    return result;
}

- (nullable UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return self.itemAttributesMap[@(indexPath.row)];
}

- (CGSize)collectionViewContentSize
{
    return self.contentSize;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds
{
    return self.collectionView.bounds.size.width != newBounds.size.width;
}

@end

NS_ASSUME_NONNULL_END
