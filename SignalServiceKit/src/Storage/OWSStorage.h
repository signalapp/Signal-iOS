//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const StorageIsReadyNotification;

@class YapDatabaseExtension;

@protocol OWSDatabaseConnectionDelegate <NSObject>

- (BOOL)areAllRegistrationsComplete;

@end

#pragma mark -

@interface OWSDatabaseConnection : YapDatabaseConnection

@property (atomic, weak) id<OWSDatabaseConnectionDelegate> delegate;

#ifdef DEBUG
@property (atomic) BOOL canWriteBeforeStorageReady;
#endif

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithDatabase:(YapDatabase *)database
                        delegate:(id<OWSDatabaseConnectionDelegate>)delegate NS_DESIGNATED_INITIALIZER;

@end

#pragma mark -

@interface OWSStorage : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initStorage NS_DESIGNATED_INITIALIZER;

// Returns YES if _ALL_ storage classes have completed both their
// sync _AND_ async view registrations.
+ (BOOL)isStorageReady;

// This object can be used to filter database notifications.
@property (nonatomic, readonly, nullable) id dbNotificationObject;

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

#ifdef DEBUG
- (BOOL)registerExtension:(YapDatabaseExtension *)extension withName:(NSString *)extensionName;
#endif
- (void)asyncRegisterExtension:(YapDatabaseExtension *)extension withName:(NSString *)extensionName;
- (nullable id)registeredExtension:(NSString *)extensionName;

- (unsigned long long)databaseFileSize;

- (YapDatabaseConnection *)registrationConnection;

#pragma mark - Password

/**
 * Returns NO if:
 *
 * - Keychain is locked because device has just been restarted.
 * - Password could not be retrieved because of a keychain error.
 */
+ (BOOL)isDatabasePasswordAccessible;

+ (nullable NSData *)tryToLoadDatabasePassword:(NSError **)errorHandle;

+ (nullable NSData *)tryToLoadDatabaseSalt:(NSError **)errorHandle;
+ (void)storeDatabaseSalt:(NSData *)saltData;

+ (nullable NSData *)tryToLoadDatabaseKeySpec:(NSError **)errorHandle;
+ (void)storeDatabaseKeySpec:(NSData *)keySpecData;

@end

NS_ASSUME_NONNULL_END
