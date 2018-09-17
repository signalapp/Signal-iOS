//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const OWSUIDatabaseConnectionWillUpdateNotification;
extern NSString *const OWSUIDatabaseConnectionDidUpdateNotification;
extern NSString *const OWSUIDatabaseConnectionWillUpdateExternallyNotification;
extern NSString *const OWSUIDatabaseConnectionDidUpdateExternallyNotification;
extern NSString *const OWSUIDatabaseConnectionNotificationsKey;

@interface OWSPrimaryStorage : OWSStorage

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initStorage;

+ (instancetype)sharedManager NS_SWIFT_NAME(shared());

@property (nonatomic, readonly) YapDatabaseConnection *uiDatabaseConnection;
@property (nonatomic, readonly) YapDatabaseConnection *dbReadConnection;
@property (nonatomic, readonly) YapDatabaseConnection *dbReadWriteConnection;

- (void)updateUIDatabaseConnectionToLatest;

+ (YapDatabaseConnection *)dbReadConnection;
+ (YapDatabaseConnection *)dbReadWriteConnection;

+ (nullable NSError *)migrateToSharedData;

+ (NSString *)databaseFilePath;

+ (NSString *)legacyDatabaseFilePath;
+ (NSString *)legacyDatabaseFilePath_SHM;
+ (NSString *)legacyDatabaseFilePath_WAL;
+ (NSString *)sharedDataDatabaseFilePath;
+ (NSString *)sharedDataDatabaseFilePath_SHM;
+ (NSString *)sharedDataDatabaseFilePath_WAL;

+ (void)protectFiles;

@end

NS_ASSUME_NONNULL_END
