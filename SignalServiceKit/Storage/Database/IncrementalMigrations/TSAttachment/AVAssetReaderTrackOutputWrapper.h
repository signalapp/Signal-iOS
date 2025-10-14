//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AVAssetReaderTrackOutputWrapper : NSObject

/// Safely creates an AVAssetReaderTrackOutput instance. Returns nil if creation fails.
+ (nullable AVAssetReaderTrackOutput *)safeAssetReaderTrackOutputWithTrack:(AVAssetTrack *)track
                                                            outputSettings:
                                                                (nullable NSDictionary<NSString *, id> *)outputSettings;

@end

NS_ASSUME_NONNULL_END
