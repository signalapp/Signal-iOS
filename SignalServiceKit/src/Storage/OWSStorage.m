//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"
#import "AppContext.h"
#import "NSData+Base64.h"
#import "NSNotificationCenter+OWS.h"
#import "NSUserDefaults+OWS.h"
#import "OWSBackgroundTask.h"
#import "OWSFileSystem.h"
#import "OWSPrimaryStorage.h"
#import "OWSStorage+Subclass.h"
#import "TSAttachmentStream.h"
#import <Curve25519Kit/Randomness.h>
#import <SAMKeychain/SAMKeychain.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseAutoView.h>
#import <YapDatabase/YapDatabaseCrossProcessNotification.h>
#import <YapDatabase/YapDatabaseCryptoUtils.h>
#import <YapDatabase/YapDatabaseSecondaryIndex.h>
#import <YapDatabase/YapDatabaseSecondaryIndexPrivate.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const StorageIsReadyNotification = @"StorageIsReadyNotification";

NSString *const OWSStorageExceptionName_DatabasePasswordInaccessibleWhileBackgrounded
    = @"OWSStorageExceptionName_DatabasePasswordInaccessibleWhileBackgrounded";
NSString *const OWSStorageExceptionName_DatabasePasswordUnwritable
    = @"OWSStorageExceptionName_DatabasePasswordUnwritable";
NSString *const OWSStorageExceptionName_NoDatabase = @"OWSStorageExceptionName_NoDatabase";
NSString *const OWSResetStorageNotification = @"OWSResetStorageNotification";

static NSString *keychainService = @"TSKeyChainService";
static NSString *keychainDBLegacyPassphrase = @"TSDatabasePass";
static NSString *keychainDBCipherKeySpec = @"OWSDatabaseCipherKeySpec";

const NSUInteger kDatabasePasswordLength = 30;

typedef NSData *_Nullable (^LoadDatabaseMetadataBlock)(NSError **_Nullable);
typedef NSData *_Nullable (^CreateDatabaseMetadataBlock)(void);

NSString *const kNSUserDefaults_DatabaseExtensionVersionMap = @"kNSUserDefaults_DatabaseExtensionVersionMap";

#pragma mark -

@interface YapDatabaseConnection ()

- (id)initWithDatabase:(YapDatabase *)database;

@end

#pragma mark -

@implementation OWSDatabaseConnection

- (id)initWithDatabase:(YapDatabase *)database delegate:(id<OWSDatabaseConnectionDelegate>)delegate
{
    self = [super initWithDatabase:database];

    if (!self) {
        return self;
    }

    OWSAssert(delegate);

    self.delegate = delegate;

    return self;
}

// Assert that the database is in a ready state (specifically that any sync database
// view registrations have completed and any async registrations have been started)
// before creating write transactions.
//
// Creating write transactions before the _sync_ database views are registered
// causes YapDatabase to rebuild all of our database views, which is catastrophic.
// Specifically, it causes YDB's "view version" checks to fail.
- (void)readWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
{
    id<OWSDatabaseConnectionDelegate> delegate = self.delegate;
    OWSAssert(delegate);
    OWSAssert(delegate.areAllRegistrationsComplete);

    OWSBackgroundTask *_Nullable backgroundTask = nil;
    if (CurrentAppContext().isMainApp) {
        backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];
    }
    [super readWriteWithBlock:block];
    backgroundTask = nil;
}

- (void)asyncReadWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
{
    [self asyncReadWriteWithBlock:block completionQueue:NULL completionBlock:NULL];
}

- (void)asyncReadWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
                completionBlock:(nullable dispatch_block_t)completionBlock
{
    [self asyncReadWriteWithBlock:block completionQueue:NULL completionBlock:completionBlock];
}

- (void)asyncReadWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
                completionQueue:(nullable dispatch_queue_t)completionQueue
                completionBlock:(nullable dispatch_block_t)completionBlock
{
    id<OWSDatabaseConnectionDelegate> delegate = self.delegate;
    OWSAssert(delegate);
    OWSAssert(delegate.areAllRegistrationsComplete);

    __block OWSBackgroundTask *_Nullable backgroundTask = nil;
    if (CurrentAppContext().isMainApp) {
        backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];
    }
    [super asyncReadWriteWithBlock:block completionQueue:completionQueue completionBlock:^{
        if (completionBlock) {
            completionBlock();
        }
        backgroundTask = nil;
    }];
}

@end

#pragma mark -

// This class is only used in DEBUG builds.
@interface YapDatabase ()

- (void)addConnection:(YapDatabaseConnection *)connection;

- (YapDatabaseConnection *)registrationConnection;

@end

#pragma mark -

@interface OWSDatabase ()

@property (atomic, weak) id<OWSDatabaseConnectionDelegate> delegate;

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

    self.delegate = delegate;

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

- (YapDatabaseConnection *)registrationConnection
{
    YapDatabaseConnection *connection = [super registrationConnection];
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

@end

#pragma mark -

@implementation OWSStorage

- (instancetype)initStorage
{
    self = [super init];

    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(resetStorage)
                                                     name:OWSResetStorageNotification
                                                   object:nil];
    }

    return self;
}

- (void)dealloc
{
    // Surface memory leaks by logging the deallocation of this class.
    DDLogVerbose(@"Dealloc: %@", self.class);

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadDatabase
{
    if (![self tryToLoadDatabase]) {
        // Failing to load the database is catastrophic.
        //
        // The best we can try to do is to discard the current database
        // and behave like a clean install.
        OWSFail(@"%@ Could not load database", self.logTag);
        OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotLoadDatabase]);

        // Try to reset app by deleting all databases.
        //
        // TODO: Possibly clean up all app files.
        // [OWSStorage deleteDatabaseFiles];

        if (![self tryToLoadDatabase]) {
            OWSFail(@"%@ Could not load database (second try)", self.logTag);
            OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotLoadDatabaseSecondAttempt]);

            // Sleep to give analytics events time to be delivered.
            [NSThread sleepForTimeInterval:15.0f];

            OWSRaiseException(OWSStorageExceptionName_NoDatabase, @"Failed to initialize database.");
        }
    }
}

- (nullable id)dbNotificationObject
{
    OWSAssert(self.database);

    return self.database;
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

- (BOOL)areAllRegistrationsComplete
{
    return self.areSyncRegistrationsComplete && self.areAsyncRegistrationsComplete;
}

- (void)runSyncRegistrations
{
    OWS_ABSTRACT_METHOD();
}

- (void)runAsyncRegistrationsWithCompletion:(void (^_Nonnull)(void))completion
{
    OWS_ABSTRACT_METHOD();
}

+ (void)registerExtensionsWithMigrationBlock:(OWSStorageMigrationBlock)migrationBlock
{
    OWSAssert(migrationBlock);

    __block OWSBackgroundTask *_Nullable backgroundTask =
        [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    [OWSPrimaryStorage.sharedManager runSyncRegistrations];

    [OWSPrimaryStorage.sharedManager runAsyncRegistrationsWithCompletion:^{
        OWSAssert(self.isStorageReady);

        [self postRegistrationCompleteNotification];

        migrationBlock();

        backgroundTask = nil;
    }];
}

- (YapDatabaseConnection *)registrationConnection
{
    return self.database.registrationConnection;
}

// Returns YES IFF all registrations are complete.
+ (void)postRegistrationCompleteNotification
{
    OWSAssert(self.isStorageReady);

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[NSNotificationCenter defaultCenter] postNotificationNameAsync:StorageIsReadyNotification
                                                                 object:nil
                                                               userInfo:nil];
    });
}

+ (BOOL)isStorageReady
{
    return OWSPrimaryStorage.sharedManager.areAllRegistrationsComplete;
}

- (BOOL)tryToLoadDatabase
{
    __weak OWSStorage *weakSelf = self;

    YapDatabaseOptions *options = [[YapDatabaseOptions alloc] init];
    options.corruptAction = YapDatabaseCorruptAction_Fail;
    options.enableMultiProcessSupport = YES;
    options.cipherKeySpecBlock = ^{
        // NOTE: It's critical that we don't capture a reference to self
        // (e.g. by using OWSAssert()) or this database will contain a
        // circular reference and will leak.
        OWSStorage *strongSelf = weakSelf;
        OWSCAssert(strongSelf);

        // Rather than compute this once and capture the value of the key
        // in the closure, we prefer to fetch the key from the keychain multiple times
        // in order to keep the key out of application memory.
        NSData *databaseKeySpec = [strongSelf databaseKeySpec];
        OWSCAssert(databaseKeySpec.length == kSQLCipherKeySpecLength);
        return databaseKeySpec;
    };

    // We leave a portion of the header decrypted so that iOS will recognize the file
    // as a SQLite database. Otherwise, because the database lives in a shared data container,
    // and our usage of sqlite's write-ahead logging retains a lock on the database, the OS
    // would kill the app/share extension as soon as it is backgrounded.
    options.cipherUnencryptedHeaderLength = kSqliteHeaderLength;

    // If any of these asserts fails, we need to verify and update
    // OWSDatabaseConverter which assumes the values of these options.
    OWSAssert(options.cipherDefaultkdfIterNumber == 0);
    OWSAssert(options.kdfIterNumber == 0);
    OWSAssert(options.cipherPageSize == 0);
    OWSAssert(options.pragmaPageSize == 0);
    OWSAssert(options.pragmaJournalSizeLimit == 0);
    OWSAssert(options.pragmaMMapSize == 0);

    // Sanity checking elsewhere asserts we should only regenerate key specs when
    // there is no existing database, so rather than lazily generate in the cipherKeySpecBlock
    // we must ensure the keyspec exists before we create the database.
    [self ensureDatabaseKeySpecExists];

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

- (YapDatabaseConnection *)newDatabaseConnection
{
    YapDatabaseConnection *dbConnection = self.database.newConnection;
    if (!dbConnection) {
        OWSRaiseException(
            @"OWSStorageExceptionName_CouldNotOpenConnection", @"Storage could not open new database connection.");
    }
    return dbConnection;
}

#pragma mark - Extension Registration

+ (void)incrementVersionOfDatabaseExtension:(NSString *)extensionName
{
    DDLogError(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    NSUserDefaults *appUserDefaults = [NSUserDefaults appUserDefaults];
    OWSAssert(appUserDefaults);
    NSMutableDictionary<NSString *, NSNumber *> *_Nullable versionMap =
        [[appUserDefaults valueForKey:kNSUserDefaults_DatabaseExtensionVersionMap] mutableCopy];
    if (!versionMap) {
        versionMap = [NSMutableDictionary new];
    }
    NSNumber *_Nullable versionSuffix = versionMap[extensionName];
    versionMap[extensionName] = @(versionSuffix.intValue + 1);
    [appUserDefaults setValue:versionMap forKey:kNSUserDefaults_DatabaseExtensionVersionMap];
    [appUserDefaults synchronize];
}

- (nullable NSString *)appendSuffixToDatabaseExtensionVersionIfNecessary:(nullable NSString *)versionTag
                                                           extensionName:(NSString *)extensionName
{
    OWSAssertIsOnMainThread();

    NSUserDefaults *appUserDefaults = [NSUserDefaults appUserDefaults];
    OWSAssert(appUserDefaults);
    NSDictionary<NSString *, NSNumber *> *_Nullable versionMap =
        [appUserDefaults valueForKey:kNSUserDefaults_DatabaseExtensionVersionMap];
    NSNumber *_Nullable versionSuffix = versionMap[extensionName];

    if (versionSuffix) {
        if (!versionTag) {
            versionTag = @"0";
        }
        NSString *result = [NSString stringWithFormat:@"%@.%@", versionTag, versionSuffix];
        DDLogWarn(@"%@ database extension version: %@ + %@ -> %@", self.logTag, versionTag, versionSuffix, result);
        return result;
    }
    return versionTag;
}

- (YapDatabaseExtension *)updateExtensionVersion:(YapDatabaseExtension *)extension withName:(NSString *)extensionName
{
    OWSAssert(extension);
    OWSAssert(extensionName.length > 0);

    if ([extension isKindOfClass:[YapDatabaseAutoView class]]) {
        YapDatabaseAutoView *databaseView = (YapDatabaseAutoView *)extension;
        YapDatabaseAutoView *databaseViewCopy = [[YapDatabaseAutoView alloc]
            initWithGrouping:databaseView.grouping
                     sorting:databaseView.sorting
                  versionTag:[self appendSuffixToDatabaseExtensionVersionIfNecessary:databaseView.versionTag
                                                                       extensionName:extensionName]
                     options:databaseView.options];
        return databaseViewCopy;
    } else if ([extension isKindOfClass:[YapDatabaseSecondaryIndex class]]) {
        YapDatabaseSecondaryIndex *secondaryIndex = (YapDatabaseSecondaryIndex *)extension;
        OWSAssert(secondaryIndex->setup);
        OWSAssert(secondaryIndex->handler);
        YapDatabaseSecondaryIndex *secondaryIndexCopy = [[YapDatabaseSecondaryIndex alloc]
            initWithSetup:secondaryIndex->setup
                  handler:secondaryIndex->handler
               versionTag:[self appendSuffixToDatabaseExtensionVersionIfNecessary:secondaryIndex.versionTag
                                                                    extensionName:extensionName]
                  options:secondaryIndex->options];
        return secondaryIndexCopy;
    } else if ([extension isKindOfClass:[YapDatabaseCrossProcessNotification class]]) {
        // versionTag doesn't matter for YapDatabaseCrossProcessNotification.
        return extension;
    } else {
        // This method needs to be able to update the versionTag of all extensions.
        // If we start using other extension types, we need to modify this method to
        // handle them as well.
        OWSProdLogAndFail(@"%@ Unknown extension type: %@", self.logTag, [extension class]);

        return extension;
    }
}

- (BOOL)registerExtension:(YapDatabaseExtension *)extension withName:(NSString *)extensionName
{
    extension = [self updateExtensionVersion:extension withName:extensionName];

    return [self.database registerExtension:extension withName:extensionName];
}

- (void)asyncRegisterExtension:(YapDatabaseExtension *)extension
                      withName:(NSString *)extensionName
{
    [self asyncRegisterExtension:extension withName:extensionName completion:nil];
}

- (void)asyncRegisterExtension:(YapDatabaseExtension *)extension
                      withName:(NSString *)extensionName
                    completion:(nullable dispatch_block_t)completion
{
    extension = [self updateExtensionVersion:extension withName:extensionName];

    [self.database asyncRegisterExtension:extension
                                 withName:extensionName
                          completionBlock:^(BOOL ready) {
                              if (!ready) {
                                  OWSFail(@"%@ asyncRegisterExtension failed: %@", self.logTag, extensionName);
                              } else {
                                  DDLogVerbose(@"%@ asyncRegisterExtension succeeded: %@", self.logTag, extensionName);
                              }

                              dispatch_async(dispatch_get_main_queue(), ^{
                                  if (completion) {
                                      completion();
                                  }
                              });
                          }];
}

- (nullable id)registeredExtension:(NSString *)extensionName
{
    return [self.database registeredExtension:extensionName];
}

#pragma mark - Password

+ (void)deleteDatabaseFiles
{
    [OWSFileSystem deleteFile:[OWSPrimaryStorage databaseFilePath]];
}

- (void)deleteDatabaseFile
{
    [OWSFileSystem deleteFile:[self databaseFilePath]];
}

- (void)resetStorage
{
    self.database = nil;

    [self deleteDatabaseFile];
}

+ (void)resetAllStorage
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OWSResetStorageNotification object:nil];

    // This might be redundant but in the spirit of thoroughness...
    [self deleteDatabaseFiles];

    [self deleteDBKeys];

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

#pragma mark - Keychain

+ (BOOL)isDatabasePasswordAccessible
{
    NSError *error;
    NSData *cipherKeySpec = [self tryToLoadDatabaseCipherKeySpec:&error];

    if (cipherKeySpec && !error) {
        return YES;
    }

    if (error) {
        DDLogWarn(@"Database key couldn't be accessed: %@", error.localizedDescription);
    }

    return NO;
}

+ (nullable NSData *)tryToLoadDatabaseLegacyPassphrase:(NSError **)errorHandle
{
    return [self tryToLoadKeyChainValue:keychainDBLegacyPassphrase errorHandle:errorHandle];
}

+ (nullable NSData *)tryToLoadDatabaseCipherKeySpec:(NSError **)errorHandle
{
    NSData *_Nullable data = [self tryToLoadKeyChainValue:keychainDBCipherKeySpec errorHandle:errorHandle];
    OWSAssert(!data || data.length == kSQLCipherKeySpecLength);

    return data;
}

+ (void)storeDatabaseCipherKeySpec:(NSData *)cipherKeySpecData
{
    OWSAssert(cipherKeySpecData.length == kSQLCipherKeySpecLength);

    [self storeKeyChainValue:cipherKeySpecData keychainKey:keychainDBCipherKeySpec];
}

+ (void)removeLegacyPassphrase
{
    DDLogInfo(@"%@ removing legacy passphrase", self.logTag);

    [SAMKeychain deletePasswordForService:keychainService account:keychainDBLegacyPassphrase];
}

- (void)ensureDatabaseKeySpecExists
{
    NSError *error;
    NSData *_Nullable keySpec = [[self class] tryToLoadDatabaseCipherKeySpec:&error];

    if (error || (keySpec.length != kSQLCipherKeySpecLength)) {
        // Because we use kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        // the keychain will be inaccessible after device restart until
        // device is unlocked for the first time.  If the app receives
        // a push notification, we won't be able to access the keychain to
        // process that notification, so we should just terminate by throwing
        // an uncaught exception.
        NSString *errorDescription = [NSString
            stringWithFormat:@"CipherKeySpec inaccessible. New install or no unlock since device restart? Error: %@",
            error];
        if (CurrentAppContext().isMainApp) {
            UIApplicationState applicationState = CurrentAppContext().mainApplicationState;
            errorDescription =
                [errorDescription stringByAppendingFormat:@", ApplicationState: %d", (int)applicationState];
        }
        DDLogError(@"%@ %@", self.logTag, errorDescription);
        [DDLog flushLog];

        if (CurrentAppContext().isMainApp) {
            if (CurrentAppContext().isInBackground) {
                // Rather than crash here, we should have already detected the situation earlier
                // and exited gracefully (in the app delegate) using isDatabasePasswordAccessible.
                // This is a last ditch effort to avoid blowing away the user's database.
                [self raiseKeySpecInaccessibleExceptionWithErrorDescription:errorDescription];
            }
        } else {
            [self raiseKeySpecInaccessibleExceptionWithErrorDescription:@"CipherKeySpec inaccessible; not main app."];
        }

        // At this point, either this is a new install so there's no existing password to retrieve
        // or the keychain has become corrupt.  Either way, we want to get back to a
        // "known good state" and behave like a new install.
        BOOL doesDBExist = [NSFileManager.defaultManager fileExistsAtPath:[self databaseFilePath]];
        if (doesDBExist) {
            OWSFail(@"%@ Could not load database metadata", self.logTag);
            OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotLoadDatabaseSecondAttempt]);
        }

        // Try to reset app by deleting database.
        [OWSStorage resetAllStorage];

        keySpec = [Randomness generateRandomBytes:(int)kSQLCipherKeySpecLength];
        [[self class] storeDatabaseCipherKeySpec:keySpec];
    }
}

- (NSData *)databaseKeySpec
{
    NSError *error;
    NSData *_Nullable keySpec = [[self class] tryToLoadDatabaseCipherKeySpec:&error];

    if (error) {
        DDLogError(@"%@ failed to fetch databaseKeySpec with error: %@", self.logTag, error);
        [self raiseKeySpecInaccessibleExceptionWithErrorDescription:@"CipherKeySpec inaccessible"];
    }

    if (keySpec.length != kSQLCipherKeySpecLength) {
        DDLogError(@"%@ keyspec had length: %lu", self.logTag, (unsigned long)keySpec.length);
        [self raiseKeySpecInaccessibleExceptionWithErrorDescription:@"CipherKeySpec invalid"];
    }

    return keySpec;
}

- (void)raiseKeySpecInaccessibleExceptionWithErrorDescription:(NSString *)errorDescription
{
    OWSAssert(CurrentAppContext().isMainApp && CurrentAppContext().isInBackground);

    // Sleep to give analytics events time to be delivered.
    [NSThread sleepForTimeInterval:5.0f];

    // Presumably this happened in response to a push notification. It's possible that the keychain is corrupted
    // but it could also just be that the user hasn't yet unlocked their device since our password is
    // kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    OWSRaiseException(OWSStorageExceptionName_DatabasePasswordInaccessibleWhileBackgrounded, @"%@", errorDescription);
}

+ (void)deleteDBKeys
{
    [SAMKeychain deletePasswordForService:keychainService account:keychainDBLegacyPassphrase];
    [SAMKeychain deletePasswordForService:keychainService account:keychainDBCipherKeySpec];
}

- (unsigned long long)databaseFileSize
{
    return [OWSFileSystem fileSizeOfPath:self.databaseFilePath].unsignedLongLongValue;
}

- (unsigned long long)databaseWALFileSize
{
    return [OWSFileSystem fileSizeOfPath:self.databaseFilePath_WAL].unsignedLongLongValue;
}

- (unsigned long long)databaseSHMFileSize
{
    return [OWSFileSystem fileSizeOfPath:self.databaseFilePath_SHM].unsignedLongLongValue;
}

+ (nullable NSData *)tryToLoadKeyChainValue:(NSString *)keychainKey errorHandle:(NSError **)errorHandle
{
    OWSAssert(keychainKey.length > 0);
    OWSAssert(errorHandle);

    return [SAMKeychain passwordDataForService:keychainService account:keychainKey error:errorHandle];
}

+ (void)storeKeyChainValue:(NSData *)data keychainKey:(NSString *)keychainKey
{
    OWSAssert(keychainKey.length > 0);
    OWSAssert(data.length > 0);

    NSError *error;
    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly];
    BOOL success = [SAMKeychain setPasswordData:data forService:keychainService account:keychainKey error:&error];
    if (!success || error) {
        OWSFail(@"%@ Could not store database metadata", self.logTag);
        OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotStoreKeychainValue]);

        // Sleep to give analytics events time to be delivered.
        [NSThread sleepForTimeInterval:15.0f];

        OWSRaiseException(
            OWSStorageExceptionName_DatabasePasswordUnwritable, @"Setting keychain value failed with error: %@", error);
    } else {
        DDLogWarn(@"%@ Successfully set new keychain value.", self.logTag);
    }
}

- (void)logFileSizes
{
    DDLogInfo(@"%@ Database file size: %@", self.logTag, [OWSFileSystem fileSizeOfPath:self.databaseFilePath]);
    DDLogInfo(@"%@ \t SHM file size: %@", self.logTag, [OWSFileSystem fileSizeOfPath:self.databaseFilePath_SHM]);
    DDLogInfo(@"%@ \t WAL file size: %@", self.logTag, [OWSFileSystem fileSizeOfPath:self.databaseFilePath_WAL]);
}

@end

NS_ASSUME_NONNULL_END
