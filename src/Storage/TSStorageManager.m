//  Created by Frederic Jacobs on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSStorageManager.h"
#import "NSData+Base64.h"
#import "OWSDisappearingMessagesFinder.h"
#import "OWSReadReceipt.h"
#import "SignalRecipient.h"
#import "TSAttachmentStream.h"
#import "TSDatabaseSecondaryIndexes.h"
#import "TSDatabaseView.h"
#import "TSInteraction.h"
#import "TSPrivacyPreferences.h"
#import "TSThread.h"
#import <25519/Randomness.h>
#import <SAMKeychain/SAMKeychain.h>
#import <YapDatabase/YapDatabaseRelationship.h>

NSString *const TSUIDatabaseConnectionDidUpdateNotification = @"TSUIDatabaseConnectionDidUpdateNotification";

NSString *const TSStorageManagerExceptionNameDatabasePasswordInaccessible = @"TSStorageManagerExceptionNameDatabasePasswordInaccessible";
NSString *const TSStorageManagerExceptionNameDatabasePasswordUnwritable = @"TSStorageManagerExceptionNameDatabasePasswordUnwritable";
NSString *const TSStorageManagerExceptionNameNoDatabase = @"TSStorageManagerExceptionNameNoDatabase";

static const NSString *const databaseName = @"Signal.sqlite";
static NSString *keychainService          = @"TSKeyChainService";
static NSString *keychainDBPassAccount    = @"TSDatabasePass";

@interface TSStorageManager ()

@property YapDatabase *database;

@end

// Some lingering TSRecipient records in the wild causing crashes.
// This is a stop gap until a proper cleanup happens.
@interface TSRecipient : NSObject <NSCoding>

@end

@interface OWSUnknownObject : NSObject <NSCoding>

@end

/**
 * A default object to returned when we can't deserialize an object from YapDB. This can prevent crashes when
 * old objects linger after their definition file is removed. The danger is that, the objects can lay in wait
 * until the next time a DB extension is added and we necessarily enumerate the entire DB.
 */
@implementation OWSUnknownObject

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    return nil;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{

}

@end

@interface OWSUnarchiverDelegate : NSObject <NSKeyedUnarchiverDelegate>

@end

@implementation OWSUnarchiverDelegate

- (nullable Class)unarchiver:(NSKeyedUnarchiver *)unarchiver cannotDecodeObjectOfClassName:(NSString *)name originalClasses:(NSArray<NSString *> *)classNames
{
    DDLogError(@"[OWSUnarchiverDelegate] Ignoring unknown class name: %@. Was the class definition deleted?", name);
    return [OWSUnknownObject class];
}

@end

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

    YapDatabaseOptions *options = [[YapDatabaseOptions alloc] init];
    options.corruptAction       = YapDatabaseCorruptAction_Fail;
    options.cipherKeyBlock      = ^{
      return [self databasePassword];
    };

    _database = [[YapDatabase alloc] initWithPath:[self dbPath]
                                       serializer:NULL
                                     deserializer:[[self class] logOnFailureDeserializer]
                                          options:options];
    if (!_database) {
        DDLogError(@"%@ Failed to initialize database.", self.tag);
        [NSException raise:TSStorageManagerExceptionNameNoDatabase format:@"Failed to initialize database."];
    }
    _dbConnection = self.newDatabaseConnection;

    return self;
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
            DDLogError(@"%@ Unarchiving key:%@ from collection:%@ and data %@ failed with error: %@",
                self.tag,
                key,
                collection,
                data,
                exception.reason);
            DDLogError(@"%@ Raising exception.", self.tag);
            @throw exception;
        }
    };
}

- (void)setupDatabase
{
    // Register extensions which are essential for rendering threads synchronously
    [TSDatabaseView registerThreadDatabaseView];
    [TSDatabaseView registerBuddyConversationDatabaseView];
    [TSDatabaseView registerUnreadDatabaseView];
    [self.database registerExtension:[TSDatabaseSecondaryIndexes registerTimeStampIndex] withName:@"idx"];

    // Register extensions which aren't essential for rendering threads async
    [TSDatabaseView asyncRegisterSecondaryDevicesDatabaseView];
    [OWSReadReceipt asyncRegisterIndexOnSenderIdAndTimestampWithDatabase:self.database];
    OWSDisappearingMessagesFinder *finder = [[OWSDisappearingMessagesFinder alloc] initWithStorageManager:self];
    [finder asyncRegisterDatabaseExtensions];
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
        DDLogError(@"Error while removing files from backup: %@", error.description);
        return;
    }
}

- (YapDatabaseConnection *)newDatabaseConnection {
    return self.database.newConnection;
}

- (TSPrivacyPreferences *)privacyPreferences
{
    return [TSPrivacyPreferences sharedInstance];
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

- (BOOL)databasePasswordAccessible
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
        switch (keyFetchError.code) {
            case errSecItemNotFound:
                dbPassword = [self createAndSetNewDatabasePassword];
                break;
            default:
                DDLogError(@"%@ Getting DB password from keychain failed with error: %@", self.tag, keyFetchError);
                [NSException raise:TSStorageManagerExceptionNameDatabasePasswordInaccessible
                            format:@"Getting DB password from keychain failed with error: %@", keyFetchError];
                break;
        }
    }

    return [dbPassword dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSString *)createAndSetNewDatabasePassword
{
    NSString *newDBPassword = [[Randomness generateRandomBytes:30] base64EncodedString];
    NSError *keySetError;
    [SAMKeychain setPassword:newDBPassword forService:keychainService account:keychainDBPassAccount error:&keySetError];
    if (keySetError) {
        DDLogError(@"%@ Setting DB password failed with error: %@", self.tag, keySetError);
        [NSException raise:TSStorageManagerExceptionNameDatabasePasswordUnwritable
                    format:@"Setting DB password failed with error: %@", keySetError];
    } else {
        DDLogError(@"Succesfully set new DB password. First launch?");
    }

    return newDBPassword;
}

#pragma mark convenience methods

- (void)purgeCollection:(NSString *)collection {
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      [transaction removeAllObjectsInCollection:collection];
    }];
}

- (void)setObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection {
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      [transaction setObject:object forKey:key inCollection:collection];
    }];
}

- (void)removeObjectForKey:(NSString *)string inCollection:(NSString *)collection {
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      [transaction removeObjectForKey:string inCollection:collection];
    }];
}

- (id)objectForKey:(NSString *)key inCollection:(NSString *)collection {
    __block NSString *object;

    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      object = [transaction objectForKey:key inCollection:collection];
    }];

    return object;
}

- (NSDictionary *)dictionaryForKey:(NSString *)key inCollection:(NSString *)collection {
    __block NSDictionary *object;

    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      object = [transaction objectForKey:key inCollection:collection];
    }];

    return object;
}

- (NSString *)stringForKey:(NSString *)key inCollection:(NSString *)collection {
    NSString *string = [self objectForKey:key inCollection:collection];

    return string;
}

- (BOOL)boolForKey:(NSString *)key inCollection:(NSString *)collection {
    NSNumber *boolNum = [self objectForKey:key inCollection:collection];

    return [boolNum boolValue];
}

- (NSData *)dataForKey:(NSString *)key inCollection:(NSString *)collection {
    NSData *data = [self objectForKey:key inCollection:collection];
    return data;
}

- (ECKeyPair *)keyPairForKey:(NSString *)key inCollection:(NSString *)collection {
    ECKeyPair *keyPair = [self objectForKey:key inCollection:collection];

    return keyPair;
}

- (PreKeyRecord *)preKeyRecordForKey:(NSString *)key inCollection:(NSString *)collection {
    PreKeyRecord *preKeyRecord = [self objectForKey:key inCollection:collection];

    return preKeyRecord;
}

- (SignedPreKeyRecord *)signedPreKeyRecordForKey:(NSString *)key inCollection:(NSString *)collection {
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

- (void)deleteThreadsAndMessages {
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      [transaction removeAllObjectsInCollection:[TSThread collection]];
      [transaction removeAllObjectsInCollection:[SignalRecipient collection]];
      [transaction removeAllObjectsInCollection:[TSInteraction collection]];
      [transaction removeAllObjectsInCollection:[TSAttachment collection]];
    }];
    [TSAttachmentStream deleteAttachments];
}

- (void)wipeSignalStorage {
    self.database = nil;
    NSError *error;

    [SAMKeychain deletePasswordForService:keychainService account:keychainDBPassAccount];
    [[NSFileManager defaultManager] removeItemAtPath:[self dbPath] error:&error];


    if (error) {
        DDLogError(@"Failed to delete database: %@", error.description);
    }

    [TSAttachmentStream deleteAttachments];

    [[self init] setupDatabase];
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
