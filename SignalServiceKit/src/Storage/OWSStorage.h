//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const StorageIsReadyNotification;

@class YapDatabaseExtension;

@protocol OWSDatabaseConnectionDelegate <NSObject>

- (BOOL)areAllRegistrationsComplete;

@end

#pragma mark -

@interface OWSDatabaseConnection : YapDatabaseConnection

@property (atomic, weak) id<OWSDatabaseConnectionDelegate> delegate;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithDatabase:(YapDatabase *)database
                        delegate:(id<OWSDatabaseConnectionDelegate>)delegate NS_DESIGNATED_INITIALIZER;

@end

#pragma mark -

@interface OWSDatabase : YapDatabase

- (instancetype)init NS_UNAVAILABLE;

- (id)initWithPath:(NSString *)inPath
        serializer:(nullable YapDatabaseSerializer)inSerializer
      deserializer:(YapDatabaseDeserializer)inDeserializer
           options:(YapDatabaseOptions *)inOptions
          delegate:(id<OWSDatabaseConnectionDelegate>)delegate NS_DESIGNATED_INITIALIZER;

@end

#pragma mark -

typedef void (^OWSStorageMigrationBlock)(void);

@interface OWSStorage : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initStorage NS_DESIGNATED_INITIALIZER;

// Returns YES if _ALL_ storage classes have completed both their
// sync _AND_ async view registrations.
+ (BOOL)isStorageReady;

// This object can be used to filter database notifications.
@property (nonatomic, readonly, nullable) id dbNotificationObject;

// migrationBlock will be invoked _off_ the main thread.
+ (void)registerExtensionsWithMigrationBlock:(OWSStorageMigrationBlock)migrationBlock;

#ifdef DEBUG
- (void)closeStorageForTests;
#endif

+ (void)resetAllStorage;

- (YapDatabaseConnection *)newDatabaseConnection;

#pragma mark - Extension Registration

+ (void)incrementVersionOfDatabaseExtension:(NSString *)extensionName;

- (BOOL)registerExtension:(YapDatabaseExtension *)extension withName:(NSString *)extensionName;

- (void)asyncRegisterExtension:(YapDatabaseExtension *)extension withName:(NSString *)extensionName;
- (void)asyncRegisterExtension:(YapDatabaseExtension *)extension
                      withName:(NSString *)extensionName
                    completion:(nullable dispatch_block_t)completion;

- (nullable id)registeredExtension:(NSString *)extensionName;

- (NSArray<NSString *> *)registeredExtensionNames;

#pragma mark -

- (unsigned long long)databaseFileSize;
- (unsigned long long)databaseWALFileSize;
- (unsigned long long)databaseSHMFileSize;

- (YapDatabaseConnection *)registrationConnection;

#pragma mark - Password

/**
 * Returns NO if:
 *
 * - Keychain is locked because device has just been restarted.
 * - Password could not be retrieved because of a keychain error.
 */
+ (BOOL)isDatabasePasswordAccessible;

+ (nullable NSData *)tryToLoadDatabaseLegacyPassphrase:(NSError **)errorHandle;
+ (void)removeLegacyPassphrase;

+ (void)storeDatabaseCipherKeySpec:(NSData *)cipherKeySpecData;

- (void)logFileSizes;

@end

NS_ASSUME_NONNULL_END
