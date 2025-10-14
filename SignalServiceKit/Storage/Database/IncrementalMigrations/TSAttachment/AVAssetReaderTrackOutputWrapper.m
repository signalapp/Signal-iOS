//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "AVAssetReaderTrackOutputWrapper.h"

@implementation AVAssetReaderTrackOutputWrapper

+ (nullable AVAssetReaderTrackOutput *)safeAssetReaderTrackOutputWithTrack:(AVAssetTrack *)track
                                                            outputSettings:
                                                                (nullable NSDictionary<NSString *, id> *)outputSettings
{
    @try {
        AVAssetReaderTrackOutput *_Nullable output =
            [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:outputSettings];
        return output;
    } @catch (NSException *exception) {
        OWSFailDebug(@"Unable to generate AVAssetReaderTrackOutput: %@", exception);
        return nil;
    }
}

@end
