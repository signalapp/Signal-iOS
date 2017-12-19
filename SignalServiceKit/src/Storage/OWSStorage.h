//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const StorageIsReadyNotification;

@class YapDatabaseExtension;

@interface OWSStorage : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initStorage NS_DESIGNATED_INITIALIZER;

+ (BOOL)isStorageReady;

/**
 * The safeBlockingMigrationsBlock block will
 * run any outstanding version migrations that are a) blocking and b) safe
 * to be run before the environment and storage is completely configured.
 *
 * Specifically, these migration should not depend on or affect the data
 * of any database view.
 */
+ (void)setupWithSafeBlockingMigrations:(void (^_Nonnull)(void))safeBlockingMigrationsBlock;

+ (void)resetAllStorage;

// TODO: Deprecate?
- (nullable YapDatabaseConnection *)newDatabaseConnection;

- (BOOL)registerExtension:(YapDatabaseExtension *)extension withName:(NSString *)extensionName;
- (void)asyncRegisterExtension:(YapDatabaseExtension *)extension
                      withName:(NSString *)extensionName
               completionBlock:(nullable void (^)(BOOL ready))completionBlock;
- (nullable id)registeredExtension:(NSString *)extensionName;

#pragma mark - Password

/**
 * Returns NO if:
 *
 * - Keychain is locked because device has just been restarted.
 * - Password could not be retrieved because of a keychain error.
 */
+ (BOOL)isDatabasePasswordAccessible;

@end

NS_ASSUME_NONNULL_END
