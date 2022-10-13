//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@class SDSKeyValueStore;

// Notes:
//
// * On disk, we only bother cleaning up files, not directories.
@interface OWSOrphanDataCleaner : NSObject

+ (SDSKeyValueStore *)keyValueStore;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

// This is exposed for the debug UI.
+ (void)auditAndCleanup:(BOOL)shouldCleanup;
// This is exposed for the tests.
+ (void)auditAndCleanup:(BOOL)shouldCleanup completion:(nullable dispatch_block_t)completion;

+ (void)auditOnLaunchIfNecessary;

@end

NS_ASSUME_NONNULL_END
