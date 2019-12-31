//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewLayout.h"
#import "Signal-Swift.h"
#import "UIView+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@interface ConversationViewLayout ()

@property (nonatomic) CGFloat lastViewWidth;
@property (nonatomic) CGSize contentSize;

@property (nonatomic, readonly) NSMutableDictionary<NSNumber *, UICollectionViewLayoutAttributes *> *itemAttributesMap;
@property (nonatomic, nullable) UICollectionViewLayoutAttributes *headerLayoutAttributes;
@property (nonatomic, nullable) UICollectionViewLayoutAttributes *footerLayoutAttributes;

// This dirty flag may be redundant with logic in UICollectionViewLayout,
// but it can't hurt and it ensures that we can safely & cheaply call
// prepareLayout from view logic to ensure that we always have a¸valid
// layout without incurring any of the (great) expense of performing an
// unnecessary layout pass.
@property (nonatomic) BOOL hasLayout;
@property (nonatomic) BOOL hasEverHadLayout;

@end

#pragma mark -

@implementation ConversationViewLayout

- (instancetype)initWithConversationStyle:(ConversationStyle *)conversationStyle
{
    if (self = [super init]) {
        _itemAttributesMap = [NSMutableDictionary new];
        _conversationStyle = conversationStyle;
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
    self.lastViewWidth = 0.f;
}

- (void)prepareLayout
{
    [super prepareLayout];

    id<ConversationViewLayoutDelegate> delegate = self.delegate;
    if (!delegate) {
        OWSFailDebug(@"Missing delegate");
        [self clearState];
        return;
    }

    if (self.collectionView.bounds.size.width <= 0.f || self.collectionView.bounds.size.height <= 0.f) {
        OWSFailDebug(@"Collection view has invalid size: %@", NSStringFromCGRect(self.collectionView.bounds));
        [self clearState];
        return;
    }

    if (self.hasLayout) {
        return;
    }
    [self clearState];
    self.hasLayout = YES;

    [self prepareLayoutOfItems];
}

- (void)prepareLayoutOfItems
{
    const CGFloat viewWidth = self.conversationStyle.viewWidth;

    NSArray<id<ConversationViewLayoutItem>> *layoutItems = self.delegate.layoutItems;

    CGFloat y = 0;

    if (layoutItems.count == 0) {
        self.footerLayoutAttributes = nil;
    } else {
        NSIndexPath *headerIndexPath = [NSIndexPath indexPathForRow:0 inSection:0];
        UICollectionViewLayoutAttributes *headerLayoutAttributes = [UICollectionViewLayoutAttributes
            layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                                         withIndexPath:headerIndexPath];

        headerLayoutAttributes.frame = CGRectMake(0, y, viewWidth, self.delegate.layoutHeaderHeight);
        self.headerLayoutAttributes = headerLayoutAttributes;
    }
    y += self.delegate.layoutHeaderHeight;
    y += self.conversationStyle.contentMarginTop;
    CGFloat contentBottom = y;

    NSInteger row = 0;
    id<ConversationViewLayoutItem> _Nullable previousLayoutItem = nil;
    for (id<ConversationViewLayoutItem> layoutItem in layoutItems) {
        if (previousLayoutItem) {
            y += [layoutItem vSpacingWithPreviousLayoutItem:previousLayoutItem];
        }

        CGSize layoutSize = CGSizeCeil([layoutItem cellSize]);

        // Ensure cell fits within view.
        OWSAssertDebug(layoutSize.width <= viewWidth);
        layoutSize.width = MIN(viewWidth, layoutSize.width);

        // All cells are "full width" and are responsible for aligning their own content.
        CGRect itemFrame = CGRectMake(0, y, viewWidth, layoutSize.height);

        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        UICollectionViewLayoutAttributes *itemAttributes =
            [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
        itemAttributes.frame = itemFrame;
        self.itemAttributesMap[@(row)] = itemAttributes;

        contentBottom = itemFrame.origin.y + itemFrame.size.height;
        y = contentBottom;
        row++;
        previousLayoutItem = layoutItem;
    }

    contentBottom += self.conversationStyle.contentMarginBottom;

    if (layoutItems.count == 0) {
        self.footerLayoutAttributes = nil;
    } else {
        NSIndexPath *footerIndexPath = [NSIndexPath indexPathForRow:(NSInteger)layoutItems.count - 1 inSection:0];
        UICollectionViewLayoutAttributes *footerLayoutAttributes = [UICollectionViewLayoutAttributes
            layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionFooter
                                         withIndexPath:footerIndexPath];

        footerLayoutAttributes.frame = CGRectMake(0, contentBottom, viewWidth, self.delegate.layoutFooterHeight);
        self.footerLayoutAttributes = footerLayoutAttributes;
        contentBottom += self.delegate.layoutFooterHeight;
    }

    self.contentSize = CGSizeMake(viewWidth, contentBottom);
    self.lastViewWidth = viewWidth;
}

- (nullable NSArray<__kindof UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect
{
    NSMutableArray<UICollectionViewLayoutAttributes *> *result = [NSMutableArray new];
    if (self.headerLayoutAttributes != nil) {
        if (CGRectIntersectsRect(rect, self.headerLayoutAttributes.frame)) {
            [result addObject:self.headerLayoutAttributes];
        }
    }
    for (UICollectionViewLayoutAttributes *itemAttributes in self.itemAttributesMap.allValues) {
        if (CGRectIntersectsRect(rect, itemAttributes.frame)) {
            [result addObject:itemAttributes];
        }
    }
    if (self.footerLayoutAttributes != nil) {
        if (CGRectIntersectsRect(rect, self.footerLayoutAttributes.frame)) {
            [result addObject:self.footerLayoutAttributes];
        }
    }
    return result;
}

- (nullable UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return self.itemAttributesMap[@(indexPath.row)];
}

- (nullable UICollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)elementKind
                                                                              atIndexPath:(NSIndexPath *)indexPath
{
    if ([elementKind isEqualToString:UICollectionElementKindSectionHeader]) {
        return self.headerLayoutAttributes;
    } else if ([elementKind isEqualToString:UICollectionElementKindSectionFooter]) {
        return self.footerLayoutAttributes;
    } else {
        return nil;
    }
}

- (CGSize)collectionViewContentSize
{
    return self.contentSize;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds
{
    return self.lastViewWidth != newBounds.size.width;
}

@end

NS_ASSUME_NONNULL_END
