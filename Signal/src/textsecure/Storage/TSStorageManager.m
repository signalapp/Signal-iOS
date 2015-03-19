//
//  TSStorageManager.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager.h"
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseRelationship.h>
#import <CocoaLumberjack/DDLog.h>
#import "CryptoTools.h"
#import "DebugLogger.h"
#import "NSData+Base64.h"

#import "TSThread.h"
#import "TSInteraction.h"
#import "TSRecipient.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"

#import <SSKeychain/SSKeychain.h>
#import "TSDatabaseView.h"
#import "TSDatabaseSecondaryIndexes.h"


NSString *const TSUIDatabaseConnectionDidUpdateNotification = @"TSUIDatabaseConnectionDidUpdateNotification";

static const NSString *const databaseName  = @"Signal.sqlite";
static NSString * keychainService          = @"TSKeyChainService";
static NSString * keychainDBPassAccount    = @"TSDatabasePass";

@interface TSStorageManager ()

@property YapDatabase *database;

@end

@implementation TSStorageManager

+ (instancetype)sharedManager {
    static TSStorageManager *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] init];
        [sharedMyManager protectSignalFiles];
    });
    return sharedMyManager;
}

- (instancetype)init {
    self = [super init];
    
    YapDatabaseOptions *options = [[YapDatabaseOptions alloc] init];
    options.corruptAction = YapDatabaseCorruptAction_Fail;
    options.cipherKeyBlock = ^{
        return [self databasePassword];
    };
    
    _database = [[YapDatabase alloc] initWithPath:[self dbPath]
                                       serializer:NULL
                                     deserializer:NULL
                                          options:options];
    _dbConnection = self.newDatabaseConnection;
    
    return self;
}

- (void)setupDatabase {
    [TSDatabaseView registerThreadDatabaseView];
    [TSDatabaseView registerBuddyConversationDatabaseView];
    [TSDatabaseView registerUnreadDatabaseView];
    
    [self.database registerExtension:[TSDatabaseSecondaryIndexes registerTimeStampIndex] withName:@"idx"];
    
    [self.database registerExtension:[[YapDatabaseRelationship alloc] init] withName:@"TSRelationships"];
}


- (void)protectSignalFiles{
    [self protectFolderAtPath:[TSAttachmentStream attachmentsFolder]];
    [self protectFolderAtPath:[self dbPath]];
    [self protectFolderAtPath:[[DebugLogger sharedInstance] logsDirectory]];
}

- (void)protectFolderAtPath:(NSString*)path {
    NSError *error;
    NSDictionary *attrs = @{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication,
                   NSURLIsExcludedFromBackupKey:@YES};
    
    
    BOOL success = [NSFileManager.defaultManager setAttributes:attrs ofItemAtPath:path error:&error];
    
    if (error || !success) {
        DDLogError(@"Error while removing files from backup: %@", error.description);
        SignalAlertView(NSLocalizedString(@"WARNING_STRING", @""), NSLocalizedString(@"DISABLING_BACKUP_FAILED", @""));
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

- (NSString*)dbPath {
    
    NSString *databasePath;
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
#if TARGET_OS_IPHONE
    NSURL *fileURL = [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSString *path = [fileURL path];
    databasePath = [path stringByAppendingFormat:@"/%@", databaseName];
#elif TARGET_OS_MAC
    
    NSString* bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSArray* urlPaths = [fileManager URLsForDirectory:NSApplicationSupportDirectory
                                            inDomains:NSUserDomainMask];
    
    NSURL* appDirectory = [[urlPaths objectAtIndex:0] URLByAppendingPathComponent:bundleID isDirectory:YES];
    
    if (![fileManager fileExistsAtPath:[appDirectory path]]) {
        [fileManager createDirectoryAtURL:appDirectory withIntermediateDirectories:NO attributes:nil error:nil];
    }
    
    databasePath = [appDirectory.filePathURL.absoluteString stringByAppendingFormat:@"/%@", databaseName];
#endif
    
    return databasePath;
}

- (NSData*)databasePassword {
    [SSKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly];
    NSString *dbPassword = [SSKeychain passwordForService:keychainService account:keychainDBPassAccount];
    
    if (!dbPassword) {
        dbPassword = [[CryptoTools generateSecureRandomData:30] base64EncodedString];
        [SSKeychain setPassword:dbPassword forService:keychainService account:keychainDBPassAccount];
        DDLogError(@"Set new password from keychain ...");
    }
    
    return [dbPassword dataUsingEncoding:NSUTF8StringEncoding];
}

#pragma mark convenience methods

- (void)purgeCollection:(NSString*)collection {
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeAllObjectsInCollection:collection];
    }];
}

- (void)setObject:(id)object forKey:(NSString*)key inCollection:(NSString*)collection {
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:object forKey:key inCollection:collection];
    }];
}

- (void)removeObjectForKey:(NSString*)string inCollection:(NSString *)collection{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeObjectForKey:string inCollection:collection];
    }];
}

- (id)objectForKey:(NSString*)key inCollection:(NSString *)collection {
    __block NSString *object;
    
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        object = [transaction objectForKey:key inCollection:collection];
    }];
    
    return object;
}

- (NSDictionary*)dictionaryForKey:(NSString*)key inCollection:(NSString *)collection {
    __block NSDictionary *object;
    
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        object = [transaction objectForKey:key inCollection:collection];
    }];
    
    return object;
}

- (NSString*)stringForKey:(NSString*)key inCollection:(NSString*)collection {
    NSString *string = [self objectForKey:key inCollection:collection];
    
    return string;
}

- (BOOL)boolForKey:(NSString*)key inCollection:(NSString*)collection {
    NSNumber *boolNum = [self objectForKey:key inCollection:collection];
    
    return [boolNum boolValue];
}

- (NSData*)dataForKey:(NSString*)key inCollection:(NSString*)collection {
    NSData *data   = [self objectForKey:key inCollection:collection];
    return data;
}

- (ECKeyPair*)keyPairForKey:(NSString*)key inCollection:(NSString*)collection {
    ECKeyPair *keyPair = [self objectForKey:key inCollection:collection];
    
    return keyPair;
}

- (PreKeyRecord*)preKeyRecordForKey:(NSString*)key inCollection:(NSString*)collection {
    PreKeyRecord *preKeyRecord = [self objectForKey:key inCollection:collection];
    
    return preKeyRecord;
}

- (SignedPreKeyRecord*)signedPreKeyRecordForKey:(NSString*)key inCollection:(NSString*)collection {
    SignedPreKeyRecord *preKeyRecord = [self objectForKey:key inCollection:collection];
    
    return preKeyRecord;
}

- (int)intForKey:(NSString*)key inCollection:(NSString*)collection {
    int integer = [[self objectForKey:key inCollection:collection] intValue];
    
    return integer;
}

- (void)setInt:(int)integer forKey:(NSString*)key inCollection:(NSString*)collection {
    [self setObject:[NSNumber numberWithInt:integer] forKey:key inCollection:collection];
}

- (void)deleteThreadsAndMessages {
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeAllObjectsInCollection:[TSThread collection]];
        [transaction removeAllObjectsInCollection:[TSRecipient collection]];
        [transaction removeAllObjectsInCollection:[TSInteraction collection]];
        [transaction removeAllObjectsInCollection:[TSAttachment collection]];
    }];
    [TSAttachmentStream deleteAttachments];
}

- (void)wipeSignalStorage{
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
