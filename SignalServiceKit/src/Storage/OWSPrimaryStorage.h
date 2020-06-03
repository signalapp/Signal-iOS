//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSPrimaryStorage : OWSStorage

- (instancetype)init NS_DESIGNATED_INITIALIZER;

@property (class, nonatomic, readonly, nullable) OWSPrimaryStorage *shared;

@property (nonatomic, readonly) YapDatabaseConnection *dbReadConnection;
@property (nonatomic, readonly) YapDatabaseConnection *dbReadWriteConnection;
@property (class, nonatomic, readonly) YapDatabaseConnection *dbReadConnection;
@property (class, nonatomic, readonly) YapDatabaseConnection *dbReadWriteConnection;

+ (nullable NSError *)migrateToSharedData;

+ (NSString *)databaseFilePath;

+ (NSString *)legacyDatabaseFilePath;
+ (NSString *)legacyDatabaseFilePath_SHM;
+ (NSString *)legacyDatabaseFilePath_WAL;
+ (NSString *)sharedDataDatabaseFilePath;
+ (NSString *)sharedDataDatabaseFilePath_SHM;
+ (NSString *)sharedDataDatabaseFilePath_WAL;

+ (NSString *)legacyDatabaseDirPath;
+ (NSString *)sharedDataDatabaseDirPath;

@end

NS_ASSUME_NONNULL_END
