//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"
#import "AppContext.h"
#import "NSNotificationCenter+OWS.h"
#import "NSUserDefaults+OWS.h"
#import "OWSBackgroundTask.h"
#import "OWSFileSystem.h"
#import "OWSPrimaryStorage.h"
#import "OWSStorage+Subclass.h"
#import "SSKEnvironment.h"
#import "TSAttachmentStream.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalServiceKit/BaseModel.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseAutoView.h>
#import <YapDatabase/YapDatabaseCrossProcessNotification.h>
#import <YapDatabase/YapDatabaseCryptoUtils.h>
#import <YapDatabase/YapDatabaseFullTextSearch.h>
#import <YapDatabase/YapDatabaseFullTextSearchPrivate.h>
#import <YapDatabase/YapDatabaseSecondaryIndex.h>
#import <YapDatabase/YapDatabaseSecondaryIndexPrivate.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSResetStorageNotification = @"OWSResetStorageNotification";

static NSString *keychainService = @"TSKeyChainService";
static NSString *keychainDBLegacyPassphrase = @"TSDatabasePass";
static NSString *keychainDBCipherKeySpec = @"OWSDatabaseCipherKeySpec";

const NSUInteger kDatabasePasswordLength = 30;

typedef NSData *_Nullable (^LoadDatabaseMetadataBlock)(NSError **_Nullable);
typedef NSData *_Nullable (^CreateDatabaseMetadataBlock)(void);

NSString *const kNSUserDefaults_DatabaseExtensionVersionMap = @"kNSUserDefaults_DatabaseExtensionVersionMap";

#pragma mark -

// This macro is only intended to be used within OWSDatabaseConnection.
#define OWSAssertCanReadYDB()                                                                                          \
    do {                                                                                                               \
        /* There's no convenient way to enforce until SSKEnvironment is configured. */                                 \
        if (!SSKEnvironment.hasShared) {                                                                               \
            return;                                                                                                    \
        }                                                                                                              \
        if (!self.databaseStorage.canReadFromYdb) {                                                                    \
            OWSLogError(@"storageMode: %@.", SSKFeatureFlags.storageModeDescription);                                  \
            OWSLogError(                                                                                               \
                @"StorageCoordinatorState: %@.", NSStringFromStorageCoordinatorState(self.storageCoordinator.state));  \
            OWSLogError(@"dataStoreForUI: %@.", NSStringForDataStore(StorageCoordinator.dataStoreForUI));              \
            switch (SSKFeatureFlags.storageModeStrictness) {                                                           \
                case StorageModeStrictnessFail:                                                                        \
                    OWSFail(@"Unexpected YDB read.");                                                                  \
                    break;                                                                                             \
                case StorageModeStrictnessFailDebug:                                                                   \
                    OWSFailDebug(@"Unexpected YDB read.");                                                             \
                    break;                                                                                             \
                case StorageModeStrictnessLog:                                                                         \
                    OWSLogError(@"Unexpected YDB read.");                                                              \
                    break;                                                                                             \
            }                                                                                                          \
        }                                                                                                              \
    } while (NO)

// This macro is only intended to be used within OWSDatabaseConnection.
#define OWSAssertCanWriteYDB()                                                                                         \
    do {                                                                                                               \
        /* There's no convenient way to enforce until SSKEnvironment is configured. */                                 \
        if (!SSKEnvironment.hasShared) {                                                                               \
            return;                                                                                                    \
        }                                                                                                              \
        if (!self.databaseStorage.canWriteToYdb) {                                                                     \
            OWSLogError(@"storageMode: %@.", SSKFeatureFlags.storageModeDescription);                                  \
            OWSLogError(                                                                                               \
                @"StorageCoordinatorState: %@.", NSStringFromStorageCoordinatorState(self.storageCoordinator.state));  \
            OWSLogError(@"dataStoreForUI: %@.", NSStringForDataStore(StorageCoordinator.dataStoreForUI));              \
            switch (SSKFeatureFlags.storageModeStrictness) {                                                           \
                case StorageModeStrictnessFail:                                                                        \
                    OWSFail(@"Unexpected YDB write.");                                                                 \
                    break;                                                                                             \
                case StorageModeStrictnessFailDebug:                                                                   \
                    OWSFailDebug(@"Unexpected YDB write.");                                                            \
                    break;                                                                                             \
                case StorageModeStrictnessLog:                                                                         \
                    OWSLogError(@"Unexpected YDB write.");                                                             \
                    break;                                                                                             \
            }                                                                                                          \
        }                                                                                                              \
    } while (NO)

#pragma mark -

@interface YapDatabaseConnection ()

- (id)initWithDatabase:(YapDatabase *)database;

@end

#pragma mark -

@implementation OWSDatabaseConnection

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (StorageCoordinator *)storageCoordinator
{
    return SSKEnvironment.shared.storageCoordinator;
}

#pragma mark -

- (id)initWithDatabase:(YapDatabase *)database delegate:(id<OWSDatabaseConnectionDelegate>)delegate
{
    self = [super initWithDatabase:database];

    if (!self) {
        return self;
    }

    OWSAssertDebug(delegate);

    self.delegate = delegate;

    return self;
}

- (void)readWithBlock:(void (^)(YapDatabaseReadTransaction *transaction))block
{
    OWSAssertCanReadYDB();

    [super readWithBlock:block];
}

- (void)asyncReadWithBlock:(void (^)(YapDatabaseReadTransaction *transaction))block
{
    OWSAssertCanReadYDB();

    [super asyncReadWithBlock:block];
}

- (void)asyncReadWithBlock:(void (^)(YapDatabaseReadTransaction *transaction))block
           completionBlock:(nullable dispatch_block_t)completionBlock
{
    OWSAssertCanReadYDB();

    [super asyncReadWithBlock:block completionBlock:completionBlock];
}

- (void)asyncReadWithBlock:(void (^)(YapDatabaseReadTransaction *transaction))block
           completionQueue:(nullable dispatch_queue_t)completionQueue
           completionBlock:(nullable dispatch_block_t)completionBlock
{
    OWSAssertCanReadYDB();

    [super asyncReadWithBlock:block completionQueue:completionQueue completionBlock:completionBlock];
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
    if (!self.isCleanupConnection) {
        OWSAssertCanWriteYDB();
    }
    id<OWSDatabaseConnectionDelegate> delegate = self.delegate;
    OWSAssertDebug(delegate);
    OWSAssertDebug(delegate.areAllRegistrationsComplete);

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
    OWSAssertCanWriteYDB();
    id<OWSDatabaseConnectionDelegate> delegate = self.delegate;
    OWSAssertDebug(delegate);
    OWSAssertDebug(delegate.areAllRegistrationsComplete);

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

    OWSAssertDebug(delegate);

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
    OWSAssertDebug(delegate);

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

@interface OWSUnknownDBObject : BaseModel <NSCoding>

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
    OWSFailDebug(@"Tried to save object from unknown collection");

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

- (void)ydb_saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSFailDebug(@"Tried to save unknown object");

    // No-op.
}

- (void)ydb_removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSFailDebug(@"Tried to remove unknown object");

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
    if ([name isEqualToString:@"TSRecipient"]) {
        OWSLogError(@"Could not decode object: %@", name);
    } else {
        OWSFailDebug(@"Could not decode object: %@", name);
    }
    OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotDecodeClass]);
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

#pragma mark - Dependencies

+ (SDSDatabaseStorage *)databaseStorage
{
    return SSKEnvironment.shared.databaseStorage;
}

+ (nullable OWSPrimaryStorage *)primaryStorage
{
    return SSKEnvironment.shared.primaryStorage;
}

#pragma mark -

- (instancetype)init
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
    // Surface memory leaks by logging the deallocation of this class.
    OWSLogVerbose(@"Dealloc: %@", self.class);

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadDatabase
{
    if (![self tryToLoadDatabase]) {
        // Failing to load the database is catastrophic.
        //
        // The best we can try to do is to discard the current database
        // and behave like a clean install.
        OWSFailDebug(@"Could not load database");
        OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotLoadDatabase]);

        // Try to reset app by deleting all databases.
        //
        // TODO: Possibly clean up all app files.
        // [OWSStorage deleteDatabaseFiles];

        if (![self tryToLoadDatabase]) {
            OWSFailDebug(@"Could not load database (second try)");
            OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotLoadDatabaseSecondAttempt]);

            // Sleep to give analytics events time to be delivered.
            [NSThread sleepForTimeInterval:15.0f];

            OWSFail(@"Failed to initialize database.");
        }
    }
}

- (nullable id)dbNotificationObject
{
    OWSAssertDebug(self.database);

    return self.database;
}

- (BOOL)areAsyncRegistrationsComplete
{
    OWSAbstractMethod();

    return NO;
}

- (BOOL)areSyncRegistrationsComplete
{
    OWSAbstractMethod();

    return NO;
}

- (BOOL)areAllRegistrationsComplete
{
    return self.areSyncRegistrationsComplete && self.areAsyncRegistrationsComplete;
}

- (void)runSyncRegistrations
{
    OWSAbstractMethod();
}

- (void)runAsyncRegistrationsWithCompletion:(void (^_Nonnull)(void))completion
{
    OWSAbstractMethod();
}

+ (void)registerExtensionsWithCompletionBlock:(OWSStorageCompletionBlock)completionBlock
{
    OWSAssertDebug(self.databaseStorage.canLoadYdb);
    OWSAssertDebug(completionBlock);

    [self.primaryStorage runSyncRegistrations];

    [self.primaryStorage runAsyncRegistrationsWithCompletion:^{
        OWSAssertDebug(self.isStorageReady);

        completionBlock();
    }];
}

- (YapDatabaseConnection *)registrationConnection
{
    return self.database.registrationConnection;
}

+ (BOOL)isStorageReady
{
    if (self.databaseStorage.canLoadYdb && !self.primaryStorage.areAllRegistrationsComplete) {
        return NO;
    }
    return YES;
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

    // If any of these asserts fails, we need to verify and update
    // OWSDatabaseConverter which assumes the values of these options.
    OWSAssertDebug(options.cipherDefaultkdfIterNumber == 0);
    OWSAssertDebug(options.kdfIterNumber == 0);
    OWSAssertDebug(options.cipherPageSize == 0);
    OWSAssertDebug(options.pragmaPageSize == 0);
    OWSAssertDebug(options.pragmaJournalSizeLimit == 0);
    OWSAssertDebug(options.pragmaMMapSize == 0);

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
        OWSCAssertDebug(strongSelf);

        // Rather than compute this once and capture the value of the key
        // in the closure, we prefer to fetch the key from the keychain multiple times
        // in order to keep the key out of application memory.
        NSData *databaseKeySpec = [strongSelf databaseKeySpec];
        OWSCAssertDebug(databaseKeySpec.length == kSQLCipherKeySpecLength);
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
            OWSFailDebug(@"can't deserialize null object: %@", collection);
            return [OWSUnknownDBObject new];
        }

        @try {
            NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
            unarchiver.delegate = unarchiverDelegate;
            return [unarchiver decodeObjectForKey:@"root"];
        } @catch (NSException *exception) {
            // Sync log in case we bail.
            OWSFailDebug(@"error deserializing object: %@, %@", collection, exception);
            OWSProdCritical([OWSAnalyticsEvents storageErrorDeserialization]);
            @throw exception;
        }
    };
}

- (YapDatabaseConnection *)newDatabaseConnection
{
    YapDatabaseConnection *dbConnection = self.database.newConnection;
    if (!dbConnection) {
        OWSFail(@"Storage could not open new database connection.");
    }
    return dbConnection;
}

#pragma mark - Extension Registration

+ (void)incrementVersionOfDatabaseExtension:(NSString *)extensionName
{
    OWSLogError(@"%@", extensionName);

    // Don't increment version of a given extension more than once
    // per launch.
    static NSMutableSet<NSString *> *incrementedViewSet = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        incrementedViewSet = [NSMutableSet new];
    });
    @synchronized(incrementedViewSet) {
        if ([incrementedViewSet containsObject:extensionName]) {
            OWSLogInfo(@"Ignoring redundant increment: %@", extensionName);
            return;
        }
        [incrementedViewSet addObject:extensionName];
    }

    NSUserDefaults *appUserDefaults = [NSUserDefaults appUserDefaults];
    OWSAssertDebug(appUserDefaults);
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
    OWSAssertDebug(appUserDefaults);
    NSDictionary<NSString *, NSNumber *> *_Nullable versionMap =
        [appUserDefaults valueForKey:kNSUserDefaults_DatabaseExtensionVersionMap];
    NSNumber *_Nullable versionSuffix = versionMap[extensionName];

    if (versionSuffix) {
        NSString *result =
            [NSString stringWithFormat:@"%@.%@", (versionTag.length < 1 ? @"0" : versionTag), versionSuffix];
        OWSLogWarn(@"database extension version: %@ + %@ -> %@", versionTag, versionSuffix, result);
        return result;
    }
    return versionTag;
}

- (YapDatabaseExtension *)updateExtensionVersion:(YapDatabaseExtension *)extension withName:(NSString *)extensionName
{
    OWSAssertDebug(extension);
    OWSAssertDebug(extensionName.length > 0);

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
        OWSAssertDebug(secondaryIndex->setup);
        OWSAssertDebug(secondaryIndex->handler);
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
        OWSFailDebug(@"Unknown extension type: %@", [extension class]);

        return extension;
    }
}

- (BOOL)registerExtension:(YapDatabaseExtension *)extension withName:(NSString *)extensionName
{
    extension = [self updateExtensionVersion:extension withName:extensionName];

    OWSAssertDebug(![self.extensionNames containsObject:extensionName]);
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

    OWSAssertDebug(![self.extensionNames containsObject:extensionName]);
    [self.extensionNames addObject:extensionName];

    [self.database asyncRegisterExtension:extension
                                 withName:extensionName
                          completionBlock:^(BOOL ready) {
                              if (!ready) {
                                  OWSFailDebug(@"asyncRegisterExtension failed: %@", extensionName);
                              } else {
                                  if (!CurrentAppContext().isRunningTests) {
                                      OWSLogVerbose(@"asyncRegisterExtension succeeded: %@", extensionName);
                                  }
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

- (NSArray<NSString *> *)registeredExtensionNames
{
    return [self.extensionNames copy];
}

#pragma mark - Password

+ (void)deleteDatabaseFiles
{
    [OWSFileSystem deleteFileIfExists:[OWSPrimaryStorage legacyDatabaseFilePath]];
    [OWSFileSystem deleteFileIfExists:[OWSPrimaryStorage legacyDatabaseFilePath_SHM]];
    [OWSFileSystem deleteFileIfExists:[OWSPrimaryStorage legacyDatabaseFilePath_WAL]];
    [OWSFileSystem deleteFileIfExists:[OWSPrimaryStorage sharedDataDatabaseFilePath]];
    [OWSFileSystem deleteFileIfExists:[OWSPrimaryStorage sharedDataDatabaseFilePath_SHM]];
    [OWSFileSystem deleteFileIfExists:[OWSPrimaryStorage sharedDataDatabaseFilePath_WAL]];
    // NOTE: It's NOT safe to delete OWSPrimaryStorage.legacyDatabaseDirPath
    //       which is the app document dir.
    [OWSFileSystem deleteContentsOfDirectory:OWSPrimaryStorage.sharedDataDatabaseDirPath];
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
    OWSLogInfo(@"");

    [[NSNotificationCenter defaultCenter] postNotificationName:OWSResetStorageNotification object:nil];

    // This might be redundant but in the spirit of thoroughness...
    [self deleteDatabaseFiles];

    [self deleteDBKeys];

    if (CurrentAppContext().isMainApp) {
        [TSAttachmentStream deleteAttachmentsFromDisk];
    }

    // TODO: Delete Profiles on Disk?
}

#pragma mark - Password

- (NSString *)databaseFilePath
{
    OWSAbstractMethod();

    return @"";
}

- (NSString *)databaseFilePath_SHM
{
    OWSAbstractMethod();

    return @"";
}

- (NSString *)databaseFilePath_WAL
{
    OWSAbstractMethod();

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
        OWSLogWarn(@"Database key couldn't be accessed: %@", error.localizedDescription);
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
    OWSAssertDebug(!data || data.length == kSQLCipherKeySpecLength);

    return data;
}

+ (void)storeDatabaseCipherKeySpec:(NSData *)cipherKeySpecData
{
    OWSAssertDebug(cipherKeySpecData.length == kSQLCipherKeySpecLength);

    [self storeKeyChainValue:cipherKeySpecData keychainKey:keychainDBCipherKeySpec];
}

+ (void)removeLegacyPassphrase
{
    OWSLogInfo(@"removing legacy passphrase");

    NSError *_Nullable error;
    BOOL result = [CurrentAppContext().keychainStorage removeWithService:keychainService
                                                                     key:keychainDBLegacyPassphrase
                                                                   error:&error];
    if (error || !result) {
        OWSFailDebug(@"could not remove legacy passphrase.");
    }
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
        OWSLogError(@"%@", errorDescription);
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

        // At this point, either:
        //
        // * This is a new install so there's no existing password to retrieve.
        // * The keychain has become corrupt.
        BOOL doesDBExist = [NSFileManager.defaultManager fileExistsAtPath:[self databaseFilePath]];
        if (doesDBExist) {
            OWSFail(@"Could not load database metadata");
            OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotLoadDatabaseSecondAttempt]);
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
        OWSLogError(@"failed to fetch databaseKeySpec with error: %@", error);
        [self raiseKeySpecInaccessibleExceptionWithErrorDescription:@"CipherKeySpec inaccessible"];
    }

    if (keySpec.length != kSQLCipherKeySpecLength) {
        OWSLogError(@"keyspec had length: %lu", (unsigned long)keySpec.length);
        [self raiseKeySpecInaccessibleExceptionWithErrorDescription:@"CipherKeySpec invalid"];
    }

    return keySpec;
}

- (void)raiseKeySpecInaccessibleExceptionWithErrorDescription:(NSString *)errorDescription
{
    OWSAssertDebug(CurrentAppContext().isMainApp && CurrentAppContext().isInBackground);

    // Sleep to give analytics events time to be delivered.
    [NSThread sleepForTimeInterval:5.0f];

    // Presumably this happened in response to a push notification. It's possible that the keychain is corrupted
    // but it could also just be that the user hasn't yet unlocked their device since our password is
    // kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    OWSFail(@"%@", errorDescription);
}

+ (void)deleteDBKeys
{
    NSError *_Nullable error;
    BOOL result = [CurrentAppContext().keychainStorage removeWithService:keychainService
                                                                     key:keychainDBLegacyPassphrase
                                                                   error:&error];
    if (error || !result) {
        OWSFailDebug(@"could not remove legacy passphrase.");
    }
    result = [CurrentAppContext().keychainStorage removeWithService:keychainService
                                                                key:keychainDBCipherKeySpec
                                                              error:&error];
    if (error || !result) {
        OWSFailDebug(@"could not remove cipher key spec.");
    }
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
    OWSAssertDebug(keychainKey.length > 0);
    OWSAssertDebug(errorHandle);

    NSData *_Nullable data =
        [CurrentAppContext().keychainStorage dataForService:keychainService key:keychainKey error:errorHandle];
    if (*errorHandle || !data) {
        OWSLogWarn(@"could not load keychain value.");
    }
    return data;
}

+ (void)storeKeyChainValue:(NSData *)data keychainKey:(NSString *)keychainKey
{
    OWSAssertDebug(keychainKey.length > 0);
    OWSAssertDebug(data.length > 0);

    NSError *error;
    BOOL success =
        [CurrentAppContext().keychainStorage setWithData:data service:keychainService key:keychainKey error:&error];
    if (!success || error) {
        OWSFailDebug(@"Could not store database metadata");
        OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotStoreKeychainValue]);

        // Sleep to give analytics events time to be delivered.
        [NSThread sleepForTimeInterval:15.0f];

        OWSFail(@"Setting keychain value failed with error: %@", error);
    } else {
        OWSLogWarn(@"Successfully set new keychain value.");
    }
}

@end

NS_ASSUME_NONNULL_END
