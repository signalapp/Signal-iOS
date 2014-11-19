//
//  TSStorageManager.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager.h"
#import <YapDatabase/YapDatabase.h>
#import <CocoaLumberjack/DDLog.h>
#import <UICKeyChainStore/UICKeyChainStore.h>
#import "CryptoTools.h"
#import "NSData+Base64.h"

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
    });
    return sharedMyManager;
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

- (NSString*)databasePassword {
    NSString *dbPassword = [UICKeyChainStore stringForKey:keychainDBPassAccount];
    
    if (!dbPassword) {
        dbPassword = [[CryptoTools generateSecureRandomData:30] base64EncodedString];
        [UICKeyChainStore setString:dbPassword forKey:keychainDBPassAccount];
    }
    
    return dbPassword;
}

- (instancetype)init {
    self = [super init];
    
    if (self) {
        self.database = [self newDatabaseInit];
    }
    
    return self;
}

- (YapDatabase*)newDatabaseInit{
    YapDatabaseOptions *options = [[YapDatabaseOptions alloc] init];
    options.corruptAction = YapDatabaseCorruptAction_Fail;
    options.passphraseBlock = ^{
        return [self databasePassword];
    };
    
    return [[YapDatabase alloc] initWithPath:[self dbPath]
                            objectSerializer:NULL
                          objectDeserializer:NULL
                          metadataSerializer:NULL
                        metadataDeserializer:NULL
                             objectSanitizer:NULL
                           metadataSanitizer:NULL
                                     options:options];
    
    
}

- (YapDatabaseConnection *)databaseConnection {
    return self.database.newConnection;
}

#pragma mark convenience methods

- (void)purgeCollection:(NSString*)collection {
    YapDatabaseConnection *dbConn = [self databaseConnection];
    
    [dbConn readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeAllObjectsInCollection:collection];
    }];
}

- (void)setObject:(id)object forKey:(NSString*)key inCollection:(NSString*)collection {
    YapDatabaseConnection *dbConn = [self databaseConnection];
    
    [dbConn readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:object forKey:key inCollection:collection];
    }];
}

- (void)removeObjectForKey:(NSString*)string inCollection:(NSString *)collection{
    YapDatabaseConnection *dbConn = [self databaseConnection];
    
    [dbConn readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeObjectForKey:string inCollection:collection];
    }];
}

- (id)objectForKey:(NSString*)key inCollection:(NSString *)collection {
    YapDatabaseConnection *dbConn = [self databaseConnection];
    __block NSString *object;
    
    [dbConn readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        object = [transaction objectForKey:key inCollection:collection];
    }];
    
    return object;
}

- (NSDictionary*)dictionaryForKey:(NSString*)key inCollection:(NSString *)collection {
    YapDatabaseConnection *dbConn = [self databaseConnection];
    __block NSDictionary *object;
    
    [dbConn readWithBlock:^(YapDatabaseReadTransaction *transaction) {
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

- (void)wipe{
    self.database = nil;
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:[self dbPath] error:&error];
    
    if (error) {
        DDLogError(@"Failed to delete database: %@", error.description);
    }
    
    self.database = [self newDatabaseInit];
}

@end
