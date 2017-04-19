//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@protocol OWSMessageMediaAdapter

- (void)setCellVisible:(BOOL)isVisible;

- (void)clearCachedMediaViews;

@end

NS_ASSUME_NONNULL_END
