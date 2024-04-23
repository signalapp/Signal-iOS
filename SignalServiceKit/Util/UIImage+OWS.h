//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@interface UIImage (normalizeImage)

- (nullable UIImage *)resizedWithMaxDimensionPoints:(CGFloat)maxDimensionPoints;
- (nullable UIImage *)resizedWithMaxDimensionPixels:(CGFloat)maxDimensionPixels;

@end

NS_ASSUME_NONNULL_END
