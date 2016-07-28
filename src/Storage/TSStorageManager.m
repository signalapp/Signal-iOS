//  Created by Frederic Jacobs on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSStorageManager.h"
#import "NSData+Base64.h"
#import "SignalRecipient.h"
#import "TSAttachmentStream.h"
#import "TSDatabaseSecondaryIndexes.h"
#import "TSDatabaseView.h"
#import "TSInteraction.h"
#import "TSThread.h"
#import <25519/Randomness.h>
#import <SSKeychain/SSKeychain.h>
#import <YapDatabase/YapDatabaseRelationship.h>

NSString *const TSUIDatabaseConnectionDidUpdateNotification = @"TSUIDatabaseConnectionDidUpdateNotification";

static const NSString *const databaseName = @"Signal.sqlite";
static NSString *keychainService          = @"TSKeyChainService";
static NSString *keychainDBPassAccount    = @"TSDatabasePass";

@interface TSStorageManager ()

@property YapDatabase *database;

@end

@implementation TSStorageManager

+ (instancetype)sharedManager {
    static TSStorageManager *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      sharedMyManager = [[self alloc] init];
#if TARGET_OS_IPHONE
      [sharedMyManager protectSignalFiles];
#endif
    });
    return sharedMyManager;
}

- (instancetype)init {
    self = [super init];

    YapDatabaseOptions *options = [[YapDatabaseOptions alloc] init];
    options.corruptAction       = YapDatabaseCorruptAction_Fail;
    options.cipherKeyBlock      = ^{
      return [self databasePassword];
    };

    _database     = [[YapDatabase alloc] initWithPath:[self dbPath] serializer:NULL deserializer:NULL options:options];
    _dbConnection = self.newDatabaseConnection;

    return self;
}

- (void)setupDatabase {
    [TSDatabaseView registerThreadDatabaseView];
    [TSDatabaseView registerBuddyConversationDatabaseView];
    [TSDatabaseView registerUnreadDatabaseView];

    [self.database registerExtension:[TSDatabaseSecondaryIndexes registerTimeStampIndex] withName:@"idx"];
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

- (BOOL)databasePasswordAccessible {
    [SSKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly];
    NSError *error;
    NSString *dbPassword = [SSKeychain passwordForService:keychainService account:keychainDBPassAccount error:&error];

    if (dbPassword && !error) {
        return YES;
    }

    if (error) {
        DDLogWarn(@"Database password couldn't be accessed: %@", error.localizedDescription);
    }

    return NO;
}

- (NSData *)databasePassword {
    [SSKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly];
    NSString *dbPassword = [SSKeychain passwordForService:keychainService account:keychainDBPassAccount];

    if (!dbPassword) {
        dbPassword = [[Randomness generateRandomBytes:30] base64EncodedString];
        [SSKeychain setPassword:dbPassword forService:keychainService account:keychainDBPassAccount];
        DDLogError(@"Set new password from keychain ...");
    }

    return [dbPassword dataUsingEncoding:NSUTF8StringEncoding];
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

    [SSKeychain deletePasswordForService:keychainService account:keychainDBPassAccount];
    [[NSFileManager defaultManager] removeItemAtPath:[self dbPath] error:&error];


    if (error) {
        DDLogError(@"Failed to delete database: %@", error.description);
    }

    [TSAttachmentStream deleteAttachments];

    [[self init] setupDatabase];
}

@end
