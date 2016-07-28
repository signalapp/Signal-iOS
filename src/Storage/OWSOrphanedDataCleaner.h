// Copyright (c) 2016 Open Whisper Systems. All rights reserved.

@interface OWSOrphanedDataCleaner : NSObject

/**
 * Remove any inaccessible data left behind due to application bugs.
 */
- (void)removeOrphanedData;

@end
