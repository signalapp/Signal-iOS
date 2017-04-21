//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@protocol OWSMessageMediaAdapter

- (void)setCellVisible:(BOOL)isVisible;

// Cells will request that this adapter clear its cached media views,
// but the adapter should only honor requests from the last cell to
// use its views.
- (void)setLastPresentingCell:(nullable id)cell;
- (void)clearCachedMediaViewsIfLastPresentingCell:(id)cell;

@end

NS_ASSUME_NONNULL_END
