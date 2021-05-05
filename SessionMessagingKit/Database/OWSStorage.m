//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"
#import "AppContext.h"
#import "OWSBackgroundTask.h"
#import "OWSFileSystem.h"
#import "OWSPrimaryStorage.h"
#import "TSYapDatabaseObject.h"
#import "TSAttachmentStream.h"
#import <SignalCoreKit/SignalCoreKit.h>
#import <SignalCoreKit/Randomness.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseAutoView.h>
#import <YapDatabase/YapDatabaseCryptoUtils.h>
#import <YapDatabase/YapDatabaseCrossProcessNotification.h>
#import <YapDatabase/YapDatabaseFullTextSearch.h>
#import <YapDatabase/YapDatabaseFullTextSearchPrivate.h>
#import <YapDatabase/YapDatabaseSecondaryIndex.h>
#import <YapDatabase/YapDatabaseSecondaryIndexPrivate.h>
#import <YapDatabase/YapDatabaseSecondaryIndexSetup.h>
#import <SessionUtilitiesKit/SessionUtilitiesKit.h>
#import <SessionUtilitiesKit/AppContext.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const StorageIsReadyNotification = @"StorageIsReadyNotification";
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
    OWSBackgroundTask *_Nullable backgroundTask = nil;
    if (CurrentAppContext().isMainApp && !CurrentAppContext().isRunningTests) {
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

@interface OWSUnknownDBObject : TSYapDatabaseObject <NSCoding>

@end

#pragma mark -

/**
 * A default object to return when we can't deserialize an object from YapDB. This can prevent crashes when
 * old objects linger after their definition file is removed. The danger is that, the objects can lay in wait
 * until the next time a DB extension is added and we necessarily enumerate the entire DB.
 */
@implementation OWSUnknownDBObject

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    return [super encodeWithCoder:aCoder];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    return self;
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    // No-op.
}

- (void)touchWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    // No-op.
}

- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    // No-op.
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
    return [OWSUnknownDBObject class];
}

@end

#pragma mark -

@interface OWSStorage () <OWSDatabaseConnectionDelegate>

@property (atomic, nullable) YapDatabase *database;

@property (nonatomic) NSMutableArray<NSString *> *extensionNames;

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

        self.extensionNames = [NSMutableArray new];
    }

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadDatabase
{
    if (![self tryToLoadDatabase]) {
        // Failing to load the database is catastrophic.
        //
        // The best we can try to do is to discard the current database
        // and behave like a clean install.

        // Try to reset app by deleting all databases.
        //
        // TODO: Possibly clean up all app files.
        // [OWSStorage deleteDatabaseFiles];

        if (![self tryToLoadDatabase]) {

            // Sleep to give analytics events time to be delivered.
            [NSThread sleepForTimeInterval:15.0f];

            NSAssert(NO, @"Couldn't load database");
        }
    }
}

- (nullable id)dbNotificationObject
{
    return self.database;
}

- (BOOL)areAsyncRegistrationsComplete
{
    return NO;
}

- (BOOL)areSyncRegistrationsComplete
{
    return NO;
}

- (BOOL)areAllRegistrationsComplete
{
    return self.areSyncRegistrationsComplete && self.areAsyncRegistrationsComplete;
}

- (void)runSyncRegistrations
{

}

- (void)runAsyncRegistrationsWithCompletion:(void (^_Nonnull)(void))completion
{

}

+ (void)registerExtensionsWithMigrationBlock:(OWSStorageMigrationBlock)migrationBlock
{
    __block OWSBackgroundTask *_Nullable backgroundTask =
        [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    [OWSPrimaryStorage.sharedManager runSyncRegistrations];

    [OWSPrimaryStorage.sharedManager runAsyncRegistrationsWithCompletion:^{
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

+ (YapDatabaseOptions *)defaultDatabaseOptions
{
    YapDatabaseOptions *options = [[YapDatabaseOptions alloc] init];
    options.corruptAction = YapDatabaseCorruptAction_Fail;
    options.enableMultiProcessSupport = YES;

    // We leave a portion of the header decrypted so that iOS will recognize the file
    // as a SQLite database. Otherwise, because the database lives in a shared data container,
    // and our usage of sqlite's write-ahead logging retains a lock on the database, the OS
    // would kill the app/share extension as soon as it is backgrounded.
    options.cipherUnencryptedHeaderLength = kSqliteHeaderLength;

    // If we want to migrate to the new cipher defaults in SQLCipher4+ we'll need to do a one time
    // migration. See the `PRAGMA cipher_migrate` documentation for details.
    // https://www.zetetic.net/sqlcipher/sqlcipher-api/#cipher_migrate
    options.legacyCipherCompatibilityVersion = 3;

    return options;
}

- (BOOL)tryToLoadDatabase
{
    __weak OWSStorage *weakSelf = self;
    YapDatabaseOptions *options = [self.class defaultDatabaseOptions];
    options.cipherKeySpecBlock = ^{
        // NOTE: It's critical that we don't capture a reference to self
        // (e.g. by using OWSAssertDebug()) or this database will contain a
        // circular reference and will leak.
        OWSStorage *strongSelf = weakSelf;

        // Rather than compute this once and capture the value of the key
        // in the closure, we prefer to fetch the key from the keychain multiple times
        // in order to keep the key out of application memory.
        NSData *databaseKeySpec = [strongSelf databaseKeySpec];
        return databaseKeySpec;
    };

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
            return [OWSUnknownDBObject new];
        }

        @try {
            NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
            unarchiver.delegate = unarchiverDelegate;
            return [unarchiver decodeObjectForKey:@"root"];
        } @catch (NSException *exception) {
            // Sync log in case we bail
            @throw exception;
        }
    };
}

- (YapDatabaseConnection *)newDatabaseConnection
{
    YapDatabaseConnection *dbConnection = self.database.newConnection;
    return dbConnection;
}

#pragma mark - Extension Registration

+ (void)incrementVersionOfDatabaseExtension:(NSString *)extensionName
{
    // Don't increment version of a given extension more than once
    // per launch.
    static NSMutableSet<NSString *> *incrementedViewSet = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        incrementedViewSet = [NSMutableSet new];
    });
    @synchronized(incrementedViewSet) {
        if ([incrementedViewSet containsObject:extensionName]) {
            return;
        }
        [incrementedViewSet addObject:extensionName];
    }

    NSUserDefaults *appUserDefaults = [NSUserDefaults appUserDefaults];
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
    NSUserDefaults *appUserDefaults = [NSUserDefaults appUserDefaults];
    NSDictionary<NSString *, NSNumber *> *_Nullable versionMap =
        [appUserDefaults valueForKey:kNSUserDefaults_DatabaseExtensionVersionMap];
    NSNumber *_Nullable versionSuffix = versionMap[extensionName];

    if (versionSuffix) {
        NSString *result =
            [NSString stringWithFormat:@"%@.%@", (versionTag.length < 1 ? @"0" : versionTag), versionSuffix];
        return result;
    }
    return versionTag;
}

- (YapDatabaseExtension *)updateExtensionVersion:(YapDatabaseExtension *)extension withName:(NSString *)extensionName
{
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
        YapDatabaseSecondaryIndex *secondaryIndexCopy = [[YapDatabaseSecondaryIndex alloc]
            initWithSetup:secondaryIndex->setup
                  handler:secondaryIndex->handler
               versionTag:[self appendSuffixToDatabaseExtensionVersionIfNecessary:secondaryIndex.versionTag
                                                                    extensionName:extensionName]
                  options:secondaryIndex->options];
        return secondaryIndexCopy;
    } else if ([extension isKindOfClass:[YapDatabaseFullTextSearch class]]) {
        YapDatabaseFullTextSearch *fullTextSearch = (YapDatabaseFullTextSearch *)extension;
        
        NSString *versionTag = [self appendSuffixToDatabaseExtensionVersionIfNecessary:fullTextSearch.versionTag extensionName:extensionName];
        YapDatabaseFullTextSearch *fullTextSearchCopy =
            [[YapDatabaseFullTextSearch alloc] initWithColumnNames:fullTextSearch->columnNames.array
                                                           options:fullTextSearch->options
                                                           handler:fullTextSearch->handler
                                                        ftsVersion:fullTextSearch->ftsVersion
                                                        versionTag:versionTag];

        return fullTextSearchCopy;
    } else if ([extension isKindOfClass:[YapDatabaseCrossProcessNotification class]]) {
        // versionTag doesn't matter for YapDatabaseCrossProcessNotification.
        return extension;
    } else {
        // This method needs to be able to update the versionTag of all extensions.
        // If we start using other extension types, we need to modify this method to
        // handle them as well.

        return extension;
    }
}

- (BOOL)registerExtension:(YapDatabaseExtension *)extension withName:(NSString *)extensionName
{
    extension = [self updateExtensionVersion:extension withName:extensionName];

    [self.extensionNames addObject:extensionName];

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

    [self.extensionNames addObject:extensionName];

    [self.database asyncRegisterExtension:extension
                                 withName:extensionName
                          completionBlock:^(BOOL ready) {
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

- (NSArray<NSString *> *)registeredExtensionNames
{
    return [self.extensionNames copy];
}

#pragma mark - Password

+ (void)deleteDatabaseFiles
{
    [OWSFileSystem deleteFile:[OWSPrimaryStorage legacyDatabaseFilePath]];
    [OWSFileSystem deleteFile:[OWSPrimaryStorage legacyDatabaseFilePath_SHM]];
    [OWSFileSystem deleteFile:[OWSPrimaryStorage legacyDatabaseFilePath_WAL]];
    [OWSFileSystem deleteFile:[OWSPrimaryStorage sharedDataDatabaseFilePath]];
    [OWSFileSystem deleteFile:[OWSPrimaryStorage sharedDataDatabaseFilePath_SHM]];
    [OWSFileSystem deleteFile:[OWSPrimaryStorage sharedDataDatabaseFilePath_WAL]];
}

- (void)closeStorageForTests
{
    [self resetStorage];

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)resetStorage
{
    self.database = nil;

    [OWSStorage deleteDatabaseFiles];
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
    return @"";
}

- (NSString *)databaseFilePath_SHM
{
    return @"";
}

- (NSString *)databaseFilePath_WAL
{
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

    return NO;
}

+ (nullable NSData *)tryToLoadDatabaseLegacyPassphrase:(NSError **)errorHandle
{
    return [self tryToLoadKeyChainValue:keychainDBLegacyPassphrase errorHandle:errorHandle];
}

+ (nullable NSData *)tryToLoadDatabaseCipherKeySpec:(NSError **)errorHandle
{
    NSData *_Nullable data = [self tryToLoadKeyChainValue:keychainDBCipherKeySpec errorHandle:errorHandle];

    return data;
}

+ (void)storeDatabaseCipherKeySpec:(NSData *)cipherKeySpecData
{
    [self storeKeyChainValue:cipherKeySpecData keychainKey:keychainDBCipherKeySpec];
}

+ (void)removeLegacyPassphrase
{
    NSError *_Nullable error;
    BOOL result = [CurrentAppContext().keychainStorage removeWithService:keychainService
                                                                     key:keychainDBLegacyPassphrase
                                                                   error:&error];
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
            UIApplicationState applicationState = CurrentAppContext().reportedApplicationState;
            errorDescription = [errorDescription
                stringByAppendingFormat:@", ApplicationState: %@", NSStringForUIApplicationState(applicationState)];
        }

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

        if (!CurrentAppContext().isRunningTests) {
            // Try to reset app by deleting database.
            [OWSStorage resetAllStorage];
        }

        keySpec = [Randomness generateRandomBytes:(int)kSQLCipherKeySpecLength];
        [[self class] storeDatabaseCipherKeySpec:keySpec];
    }
}

- (NSData *)databaseKeySpec
{
    NSError *error;
    NSData *_Nullable keySpec = [[self class] tryToLoadDatabaseCipherKeySpec:&error];

    if (error) {
        [self raiseKeySpecInaccessibleExceptionWithErrorDescription:@"CipherKeySpec inaccessible"];
    }

    if (keySpec.length != kSQLCipherKeySpecLength) {
        [self raiseKeySpecInaccessibleExceptionWithErrorDescription:@"CipherKeySpec invalid"];
    }

    return keySpec;
}

- (void)raiseKeySpecInaccessibleExceptionWithErrorDescription:(NSString *)errorDescription
{
    // Sleep to give analytics events time to be delivered.
    [NSThread sleepForTimeInterval:5.0f];

    // Presumably this happened in response to a push notification. It's possible that the keychain is corrupted
    // but it could also just be that the user hasn't yet unlocked their device since our password is
    // kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
}

+ (void)deleteDBKeys
{
    NSError *_Nullable error;
    BOOL result = [CurrentAppContext().keychainStorage removeWithService:keychainService
                                                                     key:keychainDBLegacyPassphrase
                                                                   error:&error];
    result = [CurrentAppContext().keychainStorage removeWithService:keychainService
                                                                key:keychainDBCipherKeySpec
                                                              error:&error];
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
    NSData *_Nullable data =
        [CurrentAppContext().keychainStorage dataForService:keychainService key:keychainKey error:errorHandle];
    return data;
}

+ (void)storeKeyChainValue:(NSData *)data keychainKey:(NSString *)keychainKey
{
    NSError *error;
    BOOL success =
        [CurrentAppContext().keychainStorage setWithData:data service:keychainService key:keychainKey error:&error];
    if (!success || error) {

        // Sleep to give analytics events time to be delivered.
        [NSThread sleepForTimeInterval:15.0f];

    }
}

- (void)logFileSizes
{

}

@end

NS_ASSUME_NONNULL_END
