//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager.h"
#import "NSData+Base64.h"
#import "OWSAnalytics.h"
#import "OWSDisappearingMessagesFinder.h"
#import "OWSFailedAttachmentDownloadsJob.h"
#import "OWSFailedMessagesJob.h"
#import "OWSIncomingMessageFinder.h"
#import "OWSReadReceipt.h"
#import "SignalRecipient.h"
#import "TSAttachmentStream.h"
#import "TSDatabaseSecondaryIndexes.h"
#import "TSDatabaseView.h"
#import "TSInteraction.h"
#import "TSThread.h"
#import <25519/Randomness.h>
#import <SAMKeychain/SAMKeychain.h>
#import <YapDatabase/YapDatabaseRelationship.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TSStorageManagerExceptionNameDatabasePasswordInaccessible = @"TSStorageManagerExceptionNameDatabasePasswordInaccessible";
NSString *const TSStorageManagerExceptionNameDatabasePasswordInaccessibleWhileBackgrounded =
    @"TSStorageManagerExceptionNameDatabasePasswordInaccessibleWhileBackgrounded";
NSString *const TSStorageManagerExceptionNameDatabasePasswordUnwritable = @"TSStorageManagerExceptionNameDatabasePasswordUnwritable";
NSString *const TSStorageManagerExceptionNameNoDatabase = @"TSStorageManagerExceptionNameNoDatabase";

static const NSString *const databaseName = @"Signal.sqlite";
static NSString *keychainService          = @"TSKeyChainService";
static NSString *keychainDBPassAccount    = @"TSDatabasePass";

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
    OWSProdErrorWParams(@"storage_error_could_not_decode_class", ^{
        return (@{
            @"class_name" : name,
        });
    });
    return [OWSUnknownObject class];
}

@end

#pragma mark -

@implementation TSStorageManager

+ (instancetype)sharedManager {
    static TSStorageManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] initDefault];
#if TARGET_OS_IPHONE
        [sharedManager protectSignalFiles];
#endif
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
        OWSProdCritical(@"storage_error_could_not_load_database");

        // Try to reset app by deleting database.
        // Disabled resetting storage until we have better data on why this happens.
        // [self resetSignalStorage];

        if (![self tryToLoadDatabase]) {
            OWSProdCritical(@"storage_error_could_not_load_database_second_attempt");

            // Sleep to give analytics events time to be delivered.
            [NSThread sleepForTimeInterval:15.0f];

            [NSException raise:TSStorageManagerExceptionNameNoDatabase format:@"Failed to initialize database."];
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

    _database = [[YapDatabase alloc] initWithPath:[self dbPath]
                                       serializer:NULL
                                     deserializer:[[self class] logOnFailureDeserializer]
                                          options:options];
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
            OWSProdErrorWParams(@"storage_error_deserialization", ^{
                return (@{
                    @"collection" : collection,
                    kOWSAnalyticsParameterNSExceptionName : exception.name,
                    kOWSAnalyticsParameterNSExceptionReason : exception.reason,
                    kOWSAnalyticsParameterNSExceptionClassName : NSStringFromClass([exception class]),
                });
            });
            @throw exception;
        }
    };
}

- (void)setupDatabaseWithSafeBlockingMigrations:(void (^_Nonnull)())safeBlockingMigrationsBlock
{
    // Synchronously register extensions which are essential for views.
    [TSDatabaseView registerThreadDatabaseView];
    [TSDatabaseView registerThreadInteractionsDatabaseView];
    [TSDatabaseView registerUnreadDatabaseView];
    [self.database registerExtension:[TSDatabaseSecondaryIndexes registerTimeStampIndex] withName:@"idx"];

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

    // Register extensions which aren't essential for rendering threads async
    [[OWSIncomingMessageFinder new] asyncRegisterExtension];
    [TSDatabaseView asyncRegisterSecondaryDevicesDatabaseView];
    [OWSReadReceipt asyncRegisterIndexOnSenderIdAndTimestampWithDatabase:self.database];
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

- (void)protectSignalFiles {
    [self protectFolderAtPath:[TSAttachmentStream attachmentsFolder]];
    [self protectFolderAtPath:[self dbPath]];
    [self protectFolderAtPath:[[self dbPath] stringByAppendingString:@"-shm"]];
    [self protectFolderAtPath:[[self dbPath] stringByAppendingString:@"-wal"]];
}

- (void)protectFolderAtPath:(NSString *)path {
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        return;
    }

    NSError *error;
    NSDictionary *fileProtection = @{NSFileProtectionKey : NSFileProtectionCompleteUntilFirstUserAuthentication};
    [[NSFileManager defaultManager] setAttributes:fileProtection ofItemAtPath:path error:&error];

    NSDictionary *resourcesAttrs = @{ NSURLIsExcludedFromBackupKey : @YES };

    NSURL *ressourceURL = [NSURL fileURLWithPath:path];
    BOOL success        = [ressourceURL setResourceValues:resourcesAttrs error:&error];

    if (error || !success) {
        OWSProdCriticalWNSError(@"storage_error_file_protection", error);
    }
}

- (nullable YapDatabaseConnection *)newDatabaseConnection
{
    return self.database.newConnection;
}

- (BOOL)userSetPassword {
    return FALSE;
}

- (BOOL)dbExists {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self dbPath]];
}

- (NSString *)dbPath {
    NSString *databasePath;

    NSFileManager *fileManager = [NSFileManager defaultManager];
#if TARGET_OS_IPHONE
    NSURL *fileURL = [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSString *path = [fileURL path];
    databasePath   = [path stringByAppendingFormat:@"/%@", databaseName];
#elif TARGET_OS_MAC

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSArray *urlPaths  = [fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];

    NSURL *appDirectory = [[urlPaths objectAtIndex:0] URLByAppendingPathComponent:bundleID isDirectory:YES];

    if (![fileManager fileExistsAtPath:[appDirectory path]]) {
        [fileManager createDirectoryAtURL:appDirectory withIntermediateDirectories:NO attributes:nil error:nil];
    }

    databasePath = [appDirectory.filePathURL.absoluteString stringByAppendingFormat:@"/%@", databaseName];
#endif

    return databasePath;
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
    OWSAssert([UIApplication sharedApplication].applicationState == UIApplicationStateBackground);

    // Sleep to give analytics events time to be delivered.
    [NSThread sleepForTimeInterval:5.0f];

    // Presumably this happened in response to a push notification. It's possible that the keychain is corrupted
    // but it could also just be that the user hasn't yet unlocked their device since our password is
    // kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    [NSException raise:TSStorageManagerExceptionNameDatabasePasswordInaccessibleWhileBackgrounded
                format:@"%@", errorDescription];
}

- (NSData *)databasePassword
{
    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly];

    NSError *keyFetchError;
    NSString *dbPassword =
        [SAMKeychain passwordForService:keychainService account:keychainDBPassAccount error:&keyFetchError];

    if (keyFetchError) {
        UIApplicationState applicationState = [UIApplication sharedApplication].applicationState;
        NSString *errorDescription = [NSString stringWithFormat:@"Database password inaccessible. No unlock since device restart? Error: %@ ApplicationState: %d", keyFetchError, (int)applicationState];
        DDLogError(@"%@ %@", self.tag, errorDescription);
        [DDLog flushLog];

        if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
            // TODO: Rather than crash here, we should detect the situation earlier
            // and exit gracefully - (in the app delegate?). See the `
            // This is a last ditch effort to avoid blowing away the user's database.
            [self backgroundedAppDatabasePasswordInaccessibleWithErrorDescription:errorDescription];
        }

        // At this point, either this is a new install so there's no existing password to retrieve
        // or the keychain has become corrupt.  Either way, we want to get back to a
        // "known good state" and behave like a new install.

        BOOL shouldHavePassword = [NSFileManager.defaultManager fileExistsAtPath:[self dbPath]];
        if (shouldHavePassword) {
            OWSProdCritical(@"storage_error_could_not_load_database_second_attempt");
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
        OWSProdCriticalWNSError(@"storage_error_could_not_store_database_password", keySetError);

        [self deletePasswordFromKeychain];

        // Sleep to give analytics events time to be delivered.
        [NSThread sleepForTimeInterval:15.0f];

        [NSException raise:TSStorageManagerExceptionNameDatabasePasswordUnwritable
                    format:@"Setting DB password failed with error: %@", keySetError];
    } else {
        DDLogWarn(@"Succesfully set new DB password.");
    }

    return newDBPassword;
}

#pragma mark - convenience methods

- (void)purgeCollection:(NSString *)collection {
    [self.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeAllObjectsInCollection:collection];
    }];
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

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
