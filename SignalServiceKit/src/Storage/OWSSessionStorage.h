//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSSessionStorage : OWSStorage

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

// NOTE: Do not cache references to this connection elsewhere.
//
// OWSSessionStorage will close the database when the app is in the background,
// which will invalidate thise connection.
- (YapDatabaseConnection *)dbConnection;
+ (YapDatabaseConnection *)dbConnection;

+ (NSString *)databaseDirPath;
+ (NSString *)databaseFilePath;
+ (NSString *)databaseFilePath_SHM;
+ (NSString *)databaseFilePath_WAL;

#pragma mark - Migration

- (void)migrateCollection:(NSString *)collection fromStorage:(OWSStorage *)storage valueClass:(Class)valueClass;

@end

NS_ASSUME_NONNULL_END
