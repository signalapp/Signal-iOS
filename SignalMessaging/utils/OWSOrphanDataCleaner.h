//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SDSKeyValueStore;

// Notes:
//
// * On disk, we only bother cleaning up files, not directories.
@interface OWSOrphanDataCleaner : NSObject

+ (SDSKeyValueStore *)keyValueStore;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

// This is exposed for the debug UI.
+ (void)auditAndCleanup:(BOOL)shouldCleanup;
// This is exposed for the tests.
+ (void)auditAndCleanup:(BOOL)shouldCleanup completion:(nullable dispatch_block_t)completion;

+ (void)auditOnLaunchIfNecessary;

@end

NS_ASSUME_NONNULL_END
