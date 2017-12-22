//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"
#import "AppContext.h"
#import "NSData+Base64.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSBackgroundTask.h"
#import "OWSDatabaseConnection.h"
#import "OWSFileSystem.h"
#import "OWSIdentityManager.h"
#import "OWSPrimaryCopyStorage.h"
#import "OWSSessionStorage+SessionStore.h"
#import "OWSSessionStorage.h"
#import "OWSStorage+Subclass.h"
#import "TSAttachmentStream.h"
#import "TSStorageManager.h"
#import "Threading.h"
#import <Curve25519Kit/Randomness.h>
#import <SAMKeychain/SAMKeychain.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const StorageIsReadyNotification = @"StorageIsReadyNotification";

NSString *const OWSStorageExceptionName_DatabasePasswordInaccessibleWhileBackgrounded
    = @"OWSStorageExceptionName_DatabasePasswordInaccessibleWhileBackgrounded";
NSString *const OWSStorageExceptionName_DatabasePasswordUnwritable
    = @"OWSStorageExceptionName_DatabasePasswordUnwritable";
NSString *const OWSStorageExceptionName_NoDatabase = @"OWSStorageExceptionName_NoDatabase";

static NSString *keychainService = @"TSKeyChainService";
static NSString *keychainDBPassAccount = @"TSDatabasePass";

#pragma mark -

// This class is only used in DEBUG builds.
@interface YapDatabase ()

- (void)addConnection:(YapDatabaseConnection *)connection;

@end

#pragma mark -

@interface OWSDatabase : YapDatabase

@property (atomic, weak) id<OWSDatabaseConnectionDelegate> delegate;

- (instancetype)init NS_UNAVAILABLE;
- (id)initWithPath:(NSString *)inPath
        serializer:(nullable YapDatabaseSerializer)inSerializer
      deserializer:(YapDatabaseDeserializer)inDeserializer
           options:(YapDatabaseOptions *)inOptions
          delegate:(id<OWSDatabaseConnectionDelegate>)delegate NS_DESIGNATED_INITIALIZER;

@end

#pragma mark -

@implementation OWSDatabase

- (id)initWithPath:(NSString *)inPath
        serializer:(nullable YapDatabaseSerializer)inSerializer
      deserializer:(YapDatabaseDeserializer)inDeserializer
           options:(YapDatabaseOptions *)inOptions
          delegate:(id<OWSDatabaseConnectionDelegate>)delegate
{
    self = [super initWithPath:inPath serializer:inSerializer deserializer:inDeserializer options:inOptions];

    if (!self) {
        return self;
    }

    OWSAssert(delegate);

    _delegate = delegate;

    return self;
}

// This clobbers the superclass implementation to include asserts which
// ensure that the database is in a ready state before creating write transactions.
//
// See comments in OWSDatabaseConnection.
- (YapDatabaseConnection *)newConnection
{
    id<OWSDatabaseConnectionDelegate> delegate = self.delegate;
    OWSAssert(delegate);

    OWSDatabaseConnection *connection = [[OWSDatabaseConnection alloc] initWithDatabase:self delegate:delegate];
    [self addConnection:connection];
    return connection;
}

@end

#pragma mark -

@interface OWSUnknownDBObject : NSObject <NSCoding>

@end

#pragma mark -

/**
 * A default object to return when we can't deserialize an object from YapDB. This can prevent crashes when
 * old objects linger after their definition file is removed. The danger is that, the objects can lay in wait
 * until the next time a DB extension is added and we necessarily enumerate the entire DB.
 */
@implementation OWSUnknownDBObject

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    return nil;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
}

@end

#pragma mark -

@interface OWSUnarchiverDelegate : NSObject <NSKeyedUnarchiverDelegate>

@end

#pragma mark -

@implementation OWSUnarchiverDelegate

- (nullable Class)unarchiver:(NSKeyedUnarchiver *)unarchiver
    cannotDecodeObjectOfClassName:(NSString *)name
                  originalClasses:(NSArray<NSString *> *)classNames
{
    DDLogError(@"%@ Could not decode object: %@", self.logTag, name);
    OWSProdError([OWSAnalyticsEvents storageErrorCouldNotDecodeClass]);
    return [OWSUnknownDBObject class];
}

@end

#pragma mark -

@interface OWSStorage () <OWSDatabaseConnectionDelegate>

@property (atomic, nullable) YapDatabase *database;
@property (atomic) NSInteger transactionCount;
@property (atomic, nullable) OWSBackgroundTask *backgroundTask;

@end

#pragma mark -

@implementation OWSStorage

- (instancetype)initStorage
{
    self = [super init];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:OWSApplicationDidEnterBackgroundNotification
                                               object:nil];
}

- (StorageType)storageType
{
    OWS_ABSTRACT_METHOD();

    return StorageType_Unknown;
}

- (void)openDatabase
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    if (![self tryToLoadDatabase]) {
        // Failing to load the database is catastrophic.
        //
        // The best we can try to do is to discard the current database
        // and behave like a clean install.
        OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotLoadDatabase]);

        // Try to reset app by deleting all databases.
        [self deleteDatabaseFile];

        if (![self tryToLoadDatabase]) {
            OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotLoadDatabaseSecondAttempt]);

            // Sleep to give analytics events time to be delivered.
            [NSThread sleepForTimeInterval:15.0f];

            [NSException raise:OWSStorageExceptionName_NoDatabase format:@"Failed to initialize database."];
        }
    }
}

- (void)closeDatabase
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    self.database = nil;
}

- (BOOL)areAsyncRegistrationsComplete
{
    OWS_ABSTRACT_METHOD();

    return NO;
}

- (BOOL)areSyncRegistrationsComplete
{
    OWS_ABSTRACT_METHOD();

    return NO;
}

- (void)runSyncRegistrations
{
    OWS_ABSTRACT_METHOD();
}

- (void)runAsyncRegistrationsWithCompletion:(void (^_Nonnull)(void))completion
{
    OWS_ABSTRACT_METHOD();
}

+ (NSArray<OWSStorage *> *)allStorages
{
    return @[
        TSStorageManager.sharedManager,
        OWSSessionStorage.sharedManager,
    ];
}

+ (void)setupWithSafeBlockingMigrations:(void (^_Nonnull)(void))safeBlockingMigrationsBlock
{
    OWSAssert(safeBlockingMigrationsBlock);

    for (OWSStorage *storage in self.allStorages) {
        [storage runSyncRegistrations];
    }

    // Run the blocking migrations.
    //
    // These need to run _before_ the async registered database views or
    // they will block on them, which (in the upgrade case) can block
    // return of appDidFinishLaunching... which in term can cause the
    // app to crash on launch.
    safeBlockingMigrationsBlock();

    // We need to do this _before_ anyone accesses the session or identity store state.
    //
    // None of this state is used by a view, so we can safely do this before the
    // view registrations.
    [OWSSessionStorage.sharedManager migrateFromStorageIfNecessary:TSStorageManager.sharedManager];
    [OWSIdentityManager.sharedManager migrateFromStorageIfNecessary:TSStorageManager.sharedManager];

    for (OWSStorage *storage in self.allStorages) {
        [storage runAsyncRegistrationsWithCompletion:^{
            [self postRegistrationCompleteNotificationIfPossible];
        }];
    }
}

+ (void)postRegistrationCompleteNotificationIfPossible
{
    if (!self.isStorageReady) {
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[NSNotificationCenter defaultCenter] postNotificationNameAsync:StorageIsReadyNotification
                                                                 object:nil
                                                               userInfo:nil];
    });
}

+ (BOOL)isStorageReady
{
    for (OWSStorage *storage in self.allStorages) {
        if (!storage.areAsyncRegistrationsComplete) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)tryToLoadDatabase
{

    // We determine the database password first, since a side effect of
    // this can be deleting any existing database file (if we're recovering
    // from a corrupt keychain).
    NSData *databasePassword = [self databasePassword];

    YapDatabaseOptions *options = [[YapDatabaseOptions alloc] init];
    options.corruptAction = YapDatabaseCorruptAction_Fail;
    options.cipherKeyBlock = ^{
        return databasePassword;
    };
    options.enableMultiProcessSupport = YES;

    OWSDatabase *database = [[OWSDatabase alloc] initWithPath:[self databaseFilePath]
                                                   serializer:nil
                                                 deserializer:[[self class] logOnFailureDeserializer]
                                                      options:options
                                                     delegate:self];

    if (!database) {
        return NO;
    }

    _database = database;

    return YES;
}

/**
 * NSCoding sometimes throws exceptions killing our app. We want to log that exception.
 **/
+ (YapDatabaseDeserializer)logOnFailureDeserializer
{
    OWSUnarchiverDelegate *unarchiverDelegate = [OWSUnarchiverDelegate new];

    return ^id(NSString __unused *collection, NSString __unused *key, NSData *data) {
        if (!data || data.length <= 0) {
            return nil;
        }

        @try {
            NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
            unarchiver.delegate = unarchiverDelegate;
            return [unarchiver decodeObjectForKey:@"root"];
        } @catch (NSException *exception) {
            // Sync log in case we bail.
            OWSProdError([OWSAnalyticsEvents storageErrorDeserialization]);
            @throw exception;
        }
    };
}

- (nullable YapDatabaseConnection *)newDatabaseConnection
{
    return self.database.newConnection;
}

- (BOOL)registerExtension:(YapDatabaseExtension *)extension withName:(NSString *)extensionName
{
    return [self.database registerExtension:extension withName:extensionName];
}

- (void)asyncRegisterExtension:(YapDatabaseExtension *)extension
                      withName:(NSString *)extensionName
               completionBlock:(nullable void (^)(BOOL ready))completionBlock
{
    [self.database asyncRegisterExtension:extension withName:extensionName completionBlock:completionBlock];
}

- (nullable id)registeredExtension:(NSString *)extensionName
{
    return [self.database registeredExtension:extensionName];
}

#pragma mark - Password

+ (void)deleteDatabaseFiles
{
    [OWSFileSystem deleteFileIfExists:[TSStorageManager databaseFilePath]];
    [OWSFileSystem deleteFileIfExists:[TSStorageManager databaseFilePath_SHM]];
    [OWSFileSystem deleteFileIfExists:[TSStorageManager databaseFilePath_WAL]];
    [OWSFileSystem deleteFileIfExists:[OWSPrimaryCopyStorage databaseCopiesDirPath]];
    [OWSFileSystem deleteFileIfExists:[OWSSessionStorage databaseFilePath]];
    [OWSFileSystem deleteFileIfExists:[OWSSessionStorage databaseFilePath_SHM]];
    [OWSFileSystem deleteFileIfExists:[OWSSessionStorage databaseFilePath_WAL]];
}

- (void)deleteDatabaseFile
{
    [OWSFileSystem deleteFileIfExists:[self databaseFilePath]];
    [OWSFileSystem deleteFileIfExists:[self databaseFilePath_SHM]];
    [OWSFileSystem deleteFileIfExists:[self databaseFilePath_WAL]];
}

- (void)resetStorage
{
    self.database = nil;

    [self deleteDatabaseFile];
}

+ (void)resetAllStorage
{
    for (OWSStorage *storage in self.allStorages) {
        [storage resetStorage];
    }

    // This might be redundant but in the spirit of thoroughness...
    [self deleteDatabaseFiles];

    [self deletePasswordFromKeychain];

    if (CurrentAppContext().isMainApp) {
        [TSAttachmentStream deleteAttachments];
    }

    // TODO: Delete Profiles on Disk?
}

#pragma mark - Password

- (NSString *)databaseFilePath
{
    OWS_ABSTRACT_METHOD();

    return @"";
}

- (NSString *)databaseFilePath_SHM
{
    OWS_ABSTRACT_METHOD();

    return @"";
}

- (NSString *)databaseFilePath_WAL
{
    OWS_ABSTRACT_METHOD();

    return @"";
}

#pragma mark - Password

+ (BOOL)isDatabasePasswordAccessible
{
    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly];
    NSError *error;
    NSString *dbPassword = [SAMKeychain passwordForService:keychainService account:keychainDBPassAccount error:&error];

    if (dbPassword && !error) {
        return YES;
    }

    if (error) {
        DDLogWarn(@"Database password couldn't be accessed: %@", error.localizedDescription);
    }

    return NO;
}

- (NSData *)databasePassword
{
    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly];

    NSError *keyFetchError;
    NSString *dbPassword =
        [SAMKeychain passwordForService:keychainService account:keychainDBPassAccount error:&keyFetchError];

    if (keyFetchError) {
        NSString *errorDescription =
            [NSString stringWithFormat:@"Database password inaccessible. No unlock since device restart? Error: %@",
                      keyFetchError];
        if (CurrentAppContext().isMainApp) {
            UIApplicationState applicationState = CurrentAppContext().mainApplicationState;
            errorDescription =
                [errorDescription stringByAppendingFormat:@", ApplicationState: %d", (int)applicationState];
        }
        DDLogError(@"%@ %@", self.logTag, errorDescription);
        [DDLog flushLog];

        if (CurrentAppContext().isMainApp) {
            UIApplicationState applicationState = CurrentAppContext().mainApplicationState;
            if (applicationState == UIApplicationStateBackground) {
                // TODO: Rather than crash here, we should detect the situation earlier
                // and exit gracefully - (in the app delegate?). See the `
                // This is a last ditch effort to avoid blowing away the user's database.
                [self backgroundedAppDatabasePasswordInaccessibleWithErrorDescription:errorDescription];
            }
        } else {
            [self backgroundedAppDatabasePasswordInaccessibleWithErrorDescription:
                      @"Password inaccessible; not main app."];
        }

        // At this point, either this is a new install so there's no existing password to retrieve
        // or the keychain has become corrupt.  Either way, we want to get back to a
        // "known good state" and behave like a new install.

        BOOL shouldHavePassword = [NSFileManager.defaultManager fileExistsAtPath:[self databaseFilePath]];
        if (shouldHavePassword) {
            OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotLoadDatabaseSecondAttempt]);
        }

        // Try to reset app by deleting database.
        [OWSStorage resetAllStorage];

        dbPassword = [self createAndSetNewDatabasePassword];
    }

    return [dbPassword dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSString *)createAndSetNewDatabasePassword
{
    NSString *newDBPassword = [[Randomness generateRandomBytes:30] base64EncodedString];
    NSError *keySetError;
    [SAMKeychain setPassword:newDBPassword forService:keychainService account:keychainDBPassAccount error:&keySetError];
    if (keySetError) {
        OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotStoreDatabasePassword]);

        [OWSStorage deletePasswordFromKeychain];

        // Sleep to give analytics events time to be delivered.
        [NSThread sleepForTimeInterval:15.0f];

        [NSException raise:OWSStorageExceptionName_DatabasePasswordUnwritable
                    format:@"Setting DB password failed with error: %@", keySetError];
    } else {
        DDLogWarn(@"Succesfully set new DB password.");
    }

    return newDBPassword;
}

- (void)backgroundedAppDatabasePasswordInaccessibleWithErrorDescription:(NSString *)errorDescription
{
    OWSAssert(
        CurrentAppContext().isMainApp && CurrentAppContext().mainApplicationState == UIApplicationStateBackground);

    // Sleep to give analytics events time to be delivered.
    [NSThread sleepForTimeInterval:5.0f];

    // Presumably this happened in response to a push notification. It's possible that the keychain is corrupted
    // but it could also just be that the user hasn't yet unlocked their device since our password is
    // kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    [NSException raise:OWSStorageExceptionName_DatabasePasswordInaccessibleWhileBackgrounded
                format:@"%@", errorDescription];
}

+ (void)deletePasswordFromKeychain
{
    [SAMKeychain deletePasswordForService:keychainService account:keychainDBPassAccount];
}

#pragma mark - OWSDatabaseConnectionDelegate

- (void)readTransactionWillBegin
{
    [self updateTransactionCount:+1];
}

- (void)readTransactionDidComplete
{
    [self updateTransactionCount:-1];
}

- (void)readWriteTransactionWillBegin
{
    [self updateTransactionCount:+1];
}

- (void)readWriteTransactionDidComplete
{
    [self updateTransactionCount:-1];
}

- (void)updateTransactionCount:(NSInteger)increment
{
    DispatchMainThreadSafe(^{
        NSInteger oldValue = self.transactionCount;
        NSInteger newValue = oldValue + increment;
        self.transactionCount = newValue;

        if (!CurrentAppContext().isMainApp) {
            return;
        }

        if (oldValue == 0 && newValue > 0) {
            OWSAssert(!self.backgroundTask);

            [self closeDatabaseIfNecessary];

            self.backgroundTask = [OWSBackgroundTask
                backgroundTaskWithLabel:[NSString stringWithFormat:@"%@ background task", self.logTag]
                        completionBlock:^(BackgroundTaskState backgroundTaskState) {
                            switch (backgroundTaskState) {
                                case BackgroundTaskState_Success:
                                    break;
                                case BackgroundTaskState_CouldNotStart:
                                    DDLogVerbose(@"%@ BackgroundTaskState_CouldNotStart", self.logTag);
                                    break;
                                case BackgroundTaskState_Expired:
                                    DDLogVerbose(@"%@ BackgroundTaskState_Expired", self.logTag);
                                    break;
                            }
                        }];
        } else if (oldValue > 0 && newValue == 0) {
            OWSAssert(self.backgroundTask);

            self.backgroundTask = nil;
        }
    });
}

- (void)closeDatabaseIfNecessary
{
    OWSAssertIsOnMainThread();

    // Only close the session database in the background.
    if (self.storageType != StorageType_Session) {
        return;
    }
    // Only close the database if the app is in the background.
    //
    // TODO: We need to observe SAE lifecycle events.
    if (CurrentAppContext().isMainApp && CurrentAppContext().mainApplicationState != UIApplicationStateBackground) {
        return;
    }
    // Don't close the database while there are any lingering transactions.
    if (self.transactionCount > 0) {
        return;
    }

    [self closeDatabase];
}

- (void)openDatabaseIfNecessary
{
    OWSAssertIsOnMainThread();

    if (self.database) {
        return;
    }

    [self openDatabase];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    [self closeDatabaseIfNecessary];
}

- (void)applicationWillEnterForeground
{
    [self openDatabaseIfNecessary];
}

+ (void)applicationWillEnterForeground
{
    OWSAssertIsOnMainThread();

    for (OWSStorage *storage in self.allStorages) {
        [storage applicationWillEnterForeground];
    }
}

- (unsigned long long)databaseFileSize
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *_Nullable error;
    unsigned long long fileSize =
        [[fileManager attributesOfItemAtPath:self.databaseFilePath error:&error][NSFileSize] unsignedLongLongValue];
    if (error) {
        DDLogError(@"%@ Couldn't fetch database file size: %@", self.logTag, error);
    } else {
        DDLogInfo(@"%@ Database file size: %llu", self.logTag, fileSize);
    }
    return fileSize;
}

@end

NS_ASSUME_NONNULL_END
