//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager.h"
#import "AppContext.h"
#import "NSData+Base64.h"
#import "OWSAnalytics.h"
#import "OWSBatchMessageProcessor.h"
#import "OWSDisappearingMessagesFinder.h"
#import "OWSFailedAttachmentDownloadsJob.h"
#import "OWSFailedMessagesJob.h"
#import "OWSFileSystem.h"
#import "OWSIncomingMessageFinder.h"
#import "OWSMessageReceiver.h"
#import "SignalRecipient.h"
#import "TSAttachmentStream.h"
#import "TSDatabaseSecondaryIndexes.h"
#import "TSDatabaseView.h"
#import "TSInteraction.h"
#import "TSThread.h"
#import <Curve25519Kit/Randomness.h>
#import <SAMKeychain/SAMKeychain.h>
#import <YapDatabase/YapDatabaseRelationship.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TSStorageManagerExceptionName_DatabasePasswordInaccessible
    = @"TSStorageManagerExceptionName_DatabasePasswordInaccessible";
NSString *const TSStorageManagerExceptionName_DatabasePasswordInaccessibleWhileBackgrounded
    = @"TSStorageManagerExceptionName_DatabasePasswordInaccessibleWhileBackgrounded";
NSString *const TSStorageManagerExceptionName_DatabasePasswordUnwritable
    = @"TSStorageManagerExceptionName_DatabasePasswordUnwritable";
NSString *const TSStorageManagerExceptionName_NoDatabase = @"TSStorageManagerExceptionName_NoDatabase";
NSString *const TSStorageManagerExceptionName_CouldNotMoveDatabaseFile
    = @"TSStorageManagerExceptionName_CouldNotMoveDatabaseFile";
NSString *const TSStorageManagerExceptionName_CouldNotCreateDatabaseDirectory
    = @"TSStorageManagerExceptionName_CouldNotCreateDatabaseDirectory";

static NSString *keychainService          = @"TSKeyChainService";
static NSString *keychainDBPassAccount    = @"TSDatabasePass";

#pragma mark -

// This flag is only used in DEBUG builds.
static BOOL isDatabaseInitializedFlag = NO;

NSObject *isDatabaseInitializedFlagLock()
{
    static NSObject *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [NSObject new];
    });
    return instance;
}

BOOL isDatabaseInitialized()
{
    @synchronized(isDatabaseInitializedFlagLock())
    {
        return isDatabaseInitializedFlag;
    }
}

void setDatabaseInitialized()
{
    @synchronized(isDatabaseInitializedFlagLock())
    {
        isDatabaseInitializedFlag = YES;
    }
}

#pragma mark -

@interface YapDatabaseConnection ()

- (id)initWithDatabase:(YapDatabase *)inDatabase;

@end

#pragma mark -

// This class is only used in DEBUG builds.
@interface OWSDatabaseConnection : YapDatabaseConnection

@end

#pragma mark -

@implementation OWSDatabaseConnection

// This clobbers the superclass implementation to include an assert which
// ensures that the database is in a ready state before creating write transactions.
//
// Creating write transactions before the _sync_ database views are registered
// causes YapDatabase to rebuild all of our database views, which is catastrophic.
// We're not sure why, but it causes YDB's "view version" checks to fail.
- (void)readWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
{
    OWSAssert(isDatabaseInitialized());

    [super readWriteWithBlock:block];
}

@end

#pragma mark -

// This class is only used in DEBUG builds.
@interface YapDatabase ()

- (void)addConnection:(YapDatabaseConnection *)connection;

@end

#pragma mark -

@interface OWSDatabase : YapDatabase

@end

#pragma mark -

@implementation OWSDatabase

// This clobbers the superclass implementation to include asserts which
// ensure that the database is in a ready state before creating write transactions.
//
// See comments in OWSDatabaseConnection.
- (YapDatabaseConnection *)newConnection
{
    YapDatabaseConnection *connection = [[OWSDatabaseConnection alloc] initWithDatabase:self];

    [self addConnection:connection];
    return connection;
}

@end

#pragma mark -

@interface TSStorageManager ()

@property (nullable, atomic) YapDatabase *database;

@end

#pragma mark -

// Some lingering TSRecipient records in the wild causing crashes.
// This is a stop gap until a proper cleanup happens.
@interface TSRecipient : NSObject <NSCoding>

@end

#pragma mark -

@interface OWSUnknownObject : NSObject <NSCoding>

@end

#pragma mark -

/**
 * A default object to return when we can't deserialize an object from YapDB. This can prevent crashes when
 * old objects linger after their definition file is removed. The danger is that, the objects can lay in wait
 * until the next time a DB extension is added and we necessarily enumerate the entire DB.
 */
@implementation OWSUnknownObject

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

- (nullable Class)unarchiver:(NSKeyedUnarchiver *)unarchiver cannotDecodeObjectOfClassName:(NSString *)name originalClasses:(NSArray<NSString *> *)classNames
{
    DDLogError(@"%@ Could not decode object: %@", self.logTag, name);
    OWSProdError([OWSAnalyticsEvents storageErrorCouldNotDecodeClass]);
    return [OWSUnknownObject class];
}

@end

#pragma mark -

@implementation TSStorageManager

+ (instancetype)sharedManager {
    static TSStorageManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#if TARGET_OS_IPHONE
        [TSStorageManager protectSignalFiles];
#endif

        sharedManager = [[self alloc] initDefault];
    });
    return sharedManager;
}

- (instancetype)initDefault
{
    self = [super init];

    if (![self tryToLoadDatabase]) {
        // Failing to load the database is catastrophic.
        //
        // The best we can try to do is to discard the current database
        // and behave like a clean install.
        OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotLoadDatabase]);

        // Try to reset app by deleting database.
        // Disabled resetting storage until we have better data on why this happens.
        // [self resetSignalStorage];

        if (![self tryToLoadDatabase]) {
            OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotLoadDatabaseSecondAttempt]);

            // Sleep to give analytics events time to be delivered.
            [NSThread sleepForTimeInterval:15.0f];

            [NSException raise:TSStorageManagerExceptionName_NoDatabase format:@"Failed to initialize database."];
        }

        OWSSingletonAssert();
    }

    return self;
}

- (BOOL)tryToLoadDatabase
{

    // We determine the database password first, since a side effect of
    // this can be deleting any existing database file (if we're recovering
    // from a corrupt keychain).
    NSData *databasePassword = [self databasePassword];

    YapDatabaseOptions *options = [[YapDatabaseOptions alloc] init];
    options.corruptAction       = YapDatabaseCorruptAction_Fail;
    options.cipherKeyBlock = ^{
        return databasePassword;
    };
    options.enableMultiProcessSupport = YES;

#ifdef DEBUG
    _database = [[OWSDatabase alloc] initWithPath:[self dbPath]
                                       serializer:NULL
                                     deserializer:[[self class] logOnFailureDeserializer]
                                          options:options];
#else
    _database = [[YapDatabase alloc] initWithPath:[self dbPath]
                                       serializer:NULL
                                     deserializer:[[self class] logOnFailureDeserializer]
                                          options:options];
#endif

    if (!_database) {
        return NO;
    }
    _dbReadConnection = self.newDatabaseConnection;
    _dbReadWriteConnection = self.newDatabaseConnection;

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

- (void)setupDatabaseWithSafeBlockingMigrations:(void (^_Nonnull)(void))safeBlockingMigrationsBlock
{
    // Synchronously register extensions which are essential for views.
    [TSDatabaseView registerCrossProcessNotifier];
    [TSDatabaseView registerThreadInteractionsDatabaseView];
    [TSDatabaseView registerThreadDatabaseView];
    [TSDatabaseView registerUnreadDatabaseView];
    [self.database registerExtension:[TSDatabaseSecondaryIndexes registerTimeStampIndex] withName:@"idx"];
    [OWSMessageReceiver syncRegisterDatabaseExtension:self.database];
    [OWSBatchMessageProcessor syncRegisterDatabaseExtension:self.database];

    // See comments on OWSDatabaseConnection.
    //
    // In the absence of finding documentation that can shed light on the issue we've been
    // seeing, this issue only seems to affect sync and not async registrations.  We've always
    // been opening write transactions before the async registrations complete without negative
    // consequences.
    setDatabaseInitialized();

    // Run the blocking migrations.
    //
    // These need to run _before_ the async registered database views or
    // they will block on them, which (in the upgrade case) can block
    // return of appDidFinishLaunching... which in term can cause the
    // app to crash on launch.
    safeBlockingMigrationsBlock();

    // Asynchronously register other extensions.
    //
    // All sync registrations must be done before all async registrations,
    // or the sync registrations will block on the async registrations.
    [TSDatabaseView asyncRegisterUnseenDatabaseView];
    [TSDatabaseView asyncRegisterThreadOutgoingMessagesDatabaseView];
    [TSDatabaseView asyncRegisterThreadSpecialMessagesDatabaseView];

    // Register extensions which aren't essential for rendering threads async.
    [[OWSIncomingMessageFinder new] asyncRegisterExtension];
    [TSDatabaseView asyncRegisterSecondaryDevicesDatabaseView];
    [OWSDisappearingMessagesFinder asyncRegisterDatabaseExtensions:self];
    OWSFailedMessagesJob *failedMessagesJob = [[OWSFailedMessagesJob alloc] initWithStorageManager:self];
    [failedMessagesJob asyncRegisterDatabaseExtensions];
    OWSFailedAttachmentDownloadsJob *failedAttachmentDownloadsMessagesJob =
        [[OWSFailedAttachmentDownloadsJob alloc] initWithStorageManager:self];
    [failedAttachmentDownloadsMessagesJob asyncRegisterDatabaseExtensions];

    // NOTE: [TSDatabaseView asyncRegistrationCompletion] ensures that
    // kNSNotificationName_DatabaseViewRegistrationComplete is not fired until all
    // of the async registrations are complete.
    [TSDatabaseView asyncRegistrationCompletion];
}

+ (void)protectSignalFiles
{
    // The old database location was in the Document directory,
    // so protect the database files individually.
    [OWSFileSystem protectFolderAtPath:self.legacyDatabaseFilePath];
    [OWSFileSystem protectFolderAtPath:self.legacyDatabaseFilePath_SHM];
    [OWSFileSystem protectFolderAtPath:self.legacyDatabaseFilePath_WAL];

    // Protect the entire new database directory.
    [OWSFileSystem protectFolderAtPath:self.sharedDataDatabaseDirPath];
}

- (nullable YapDatabaseConnection *)newDatabaseConnection
{
    return self.database.newConnection;
}

- (BOOL)userSetPassword {
    return FALSE;
}

+ (NSString *)legacyDatabaseDirPath
{
    return [OWSFileSystem appDocumentDirectoryPath];
}

+ (NSString *)sharedDataDatabaseDirPath
{
    NSString *databaseDirPath = [[OWSFileSystem appSharedDataDirectoryPath] stringByAppendingPathComponent:@"database"];

    if (![OWSFileSystem ensureDirectoryExists:databaseDirPath]) {
        [NSException raise:TSStorageManagerExceptionName_CouldNotCreateDatabaseDirectory
                    format:@"Could not create new database directory"];
    }
    return databaseDirPath;
}

+ (NSString *)databaseFilename
{
    return @"Signal.sqlite";
}

+ (NSString *)databaseFilename_SHM
{
    return [self.databaseFilename stringByAppendingString:@"-shm"];
}

+ (NSString *)databaseFilename_WAL
{
    return [self.databaseFilename stringByAppendingString:@"-wal"];
}

+ (NSString *)legacyDatabaseFilePath
{
    return [self.legacyDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename];
}

+ (NSString *)legacyDatabaseFilePath_SHM
{
    return [self.legacyDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename_SHM];
}

+ (NSString *)legacyDatabaseFilePath_WAL
{
    return [self.legacyDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename_WAL];
}

+ (NSString *)sharedDataDatabaseFilePath
{
    return [self.sharedDataDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename];
}

+ (NSString *)sharedDataDatabaseFilePath_SHM
{
    return [self.sharedDataDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename_SHM];
}

+ (NSString *)sharedDataDatabaseFilePath_WAL
{
    return [self.sharedDataDatabaseDirPath stringByAppendingPathComponent:self.databaseFilename_WAL];
}

+ (void)migrateToSharedData
{
    [OWSFileSystem moveAppFilePath:self.legacyDatabaseFilePath
                sharedDataFilePath:self.sharedDataDatabaseFilePath
                     exceptionName:TSStorageManagerExceptionName_CouldNotMoveDatabaseFile];
    [OWSFileSystem moveAppFilePath:self.legacyDatabaseFilePath_SHM
                sharedDataFilePath:self.sharedDataDatabaseFilePath_SHM
                     exceptionName:TSStorageManagerExceptionName_CouldNotMoveDatabaseFile];
    [OWSFileSystem moveAppFilePath:self.legacyDatabaseFilePath_WAL
                sharedDataFilePath:self.sharedDataDatabaseFilePath_WAL
                     exceptionName:TSStorageManagerExceptionName_CouldNotMoveDatabaseFile];
}

- (NSString *)dbPath
{
    DDLogVerbose(@"databasePath: %@", TSStorageManager.sharedDataDatabaseFilePath);

    return TSStorageManager.sharedDataDatabaseFilePath;
}

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

- (void)backgroundedAppDatabasePasswordInaccessibleWithErrorDescription:(NSString *)errorDescription
{
    OWSAssert(
        CurrentAppContext().isMainApp && CurrentAppContext().mainApplicationState == UIApplicationStateBackground);

    // Sleep to give analytics events time to be delivered.
    [NSThread sleepForTimeInterval:5.0f];

    // Presumably this happened in response to a push notification. It's possible that the keychain is corrupted
    // but it could also just be that the user hasn't yet unlocked their device since our password is
    // kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    [NSException raise:TSStorageManagerExceptionName_DatabasePasswordInaccessibleWhileBackgrounded
                format:@"%@", errorDescription];
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

        BOOL shouldHavePassword = [NSFileManager.defaultManager fileExistsAtPath:[self dbPath]];
        if (shouldHavePassword) {
            OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotLoadDatabaseSecondAttempt]);
        }

        // Try to reset app by deleting database.
        [self resetSignalStorage];

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

        [self deletePasswordFromKeychain];

        // Sleep to give analytics events time to be delivered.
        [NSThread sleepForTimeInterval:15.0f];

        [NSException raise:TSStorageManagerExceptionName_DatabasePasswordUnwritable
                    format:@"Setting DB password failed with error: %@", keySetError];
    } else {
        DDLogWarn(@"Succesfully set new DB password.");
    }

    return newDBPassword;
}

#pragma mark - convenience methods

- (void)purgeCollection:(NSString *)collection {
    [self.dbReadWriteConnection purgeCollection:collection];
}

- (void)setObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection {
    [self.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:object forKey:key inCollection:collection];
    }];
}

- (void)removeObjectForKey:(NSString *)string inCollection:(NSString *)collection {
    [self.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeObjectForKey:string inCollection:collection];
    }];
}

- (id)objectForKey:(NSString *)key inCollection:(NSString *)collection {
    __block NSString *object;

    [self.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        object = [transaction objectForKey:key inCollection:collection];
    }];

    return object;
}

- (nullable NSDictionary *)dictionaryForKey:(NSString *)key inCollection:(NSString *)collection
{
    __block NSDictionary *object;

    [self.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        object = [transaction objectForKey:key inCollection:collection];
    }];

    return object;
}

- (nullable NSString *)stringForKey:(NSString *)key inCollection:(NSString *)collection
{
    NSString *string = [self objectForKey:key inCollection:collection];

    return string;
}

- (BOOL)boolForKey:(NSString *)key inCollection:(NSString *)collection {
    NSNumber *boolNum = [self objectForKey:key inCollection:collection];

    return [boolNum boolValue];
}

- (nullable NSData *)dataForKey:(NSString *)key inCollection:(NSString *)collection
{
    NSData *data = [self objectForKey:key inCollection:collection];
    return data;
}

- (nullable ECKeyPair *)keyPairForKey:(NSString *)key inCollection:(NSString *)collection
{
    ECKeyPair *keyPair = [self objectForKey:key inCollection:collection];

    return keyPair;
}

- (nullable PreKeyRecord *)preKeyRecordForKey:(NSString *)key inCollection:(NSString *)collection
{
    PreKeyRecord *preKeyRecord = [self objectForKey:key inCollection:collection];

    return preKeyRecord;
}

- (nullable SignedPreKeyRecord *)signedPreKeyRecordForKey:(NSString *)key inCollection:(NSString *)collection
{
    SignedPreKeyRecord *preKeyRecord = [self objectForKey:key inCollection:collection];

    return preKeyRecord;
}

- (int)intForKey:(NSString *)key inCollection:(NSString *)collection {
    int integer = [[self objectForKey:key inCollection:collection] intValue];

    return integer;
}

- (void)setInt:(int)integer forKey:(NSString *)key inCollection:(NSString *)collection {
    [self setObject:[NSNumber numberWithInt:integer] forKey:key inCollection:collection];
}

- (int)incrementIntForKey:(NSString *)key inCollection:(NSString *)collection
{
    __block int value = 0;
    [self.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        value = [[transaction objectForKey:key inCollection:collection] intValue];
        value++;
        [transaction setObject:@(value) forKey:key inCollection:collection];
    }];
    return value;
}

- (nullable NSDate *)dateForKey:(NSString *)key inCollection:(NSString *)collection
{
    NSNumber *value = [self objectForKey:key inCollection:collection];
    if (value) {
        return [NSDate dateWithTimeIntervalSince1970:value.doubleValue];
    } else {
        return nil;
    }
}

- (void)setDate:(NSDate *)value forKey:(NSString *)key inCollection:(NSString *)collection
{
    [self setObject:@(value.timeIntervalSince1970) forKey:key inCollection:collection];
}

- (void)deleteThreadsAndMessages {
    [self.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeAllObjectsInCollection:[TSThread collection]];
        [transaction removeAllObjectsInCollection:[SignalRecipient collection]];
        [transaction removeAllObjectsInCollection:[TSInteraction collection]];
        [transaction removeAllObjectsInCollection:[TSAttachment collection]];
    }];
    [TSAttachmentStream deleteAttachments];
}

- (void)deletePasswordFromKeychain
{
    [SAMKeychain deletePasswordForService:keychainService account:keychainDBPassAccount];
}

- (void)deleteDatabaseFile
{
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:[self dbPath] error:&error];
    if (error) {
        DDLogError(@"Failed to delete database: %@", error.description);
    }
}

- (void)resetSignalStorage
{
    self.database = nil;
    _dbReadConnection = nil;
    _dbReadWriteConnection = nil;

    [self deletePasswordFromKeychain];

    [self deleteDatabaseFile];

    [TSAttachmentStream deleteAttachments];
}

@end

NS_ASSUME_NONNULL_END
