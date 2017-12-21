//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSSessionStorage.h"
#import "OWSFileSystem.h"
#import "OWSStorage+Subclass.h"
#import "TSDatabaseView.h"
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSSessionStorageExceptionName_CouldNotCreateDatabaseDirectory
    = @"OWSSessionStorageExceptionName_CouldNotCreateDatabaseDirectory";

#pragma mark -

@interface OWSSessionStorage ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@property (atomic) BOOL areAsyncRegistrationsComplete;
@property (atomic) BOOL areSyncRegistrationsComplete;

@end

#pragma mark -

@implementation OWSSessionStorage

@synthesize dbConnection = _dbConnection;

+ (instancetype)sharedManager
{
    static OWSSessionStorage *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] initStorage];

#if TARGET_OS_IPHONE
        [OWSSessionStorage protectFiles];
#endif
    });
    return sharedManager;
}

- (instancetype)initStorage
{
    self = [super initStorage];

    if (self) {
        OWSSingletonAssert();
    }

    return self;
}

- (StorageType)storageType
{
    return StorageType_Session;
}

- (void)openDatabase
{
    [super openDatabase];

    _dbConnection = self.newDatabaseConnection;

    self.dbConnection.objectCacheEnabled = NO;
#if DEBUG
    self.dbConnection.permittedTransactions = YDB_AnySyncTransaction;
#endif
}

- (void)closeDatabase
{
    [super closeDatabase];

    _dbConnection = nil;
}

- (void)resetStorage
{
    _dbConnection = nil;

    [super resetStorage];
}

- (void)runSyncRegistrations
{
    // Synchronously register extensions which are essential for views.
    [TSDatabaseView registerCrossProcessNotifier:self];

    OWSAssert(!self.areSyncRegistrationsComplete);
    self.areSyncRegistrationsComplete = YES;
}

- (void)runAsyncRegistrationsWithCompletion:(void (^_Nonnull)(void))completion
{
    OWSAssert(completion);

    // Asynchronously register other extensions.
    //
    // All sync registrations must be done before all async registrations,
    // or the sync registrations will block on the async registrations.

    // Block until all async registrations are complete.
    [self.newDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        OWSAssert(!self.areAsyncRegistrationsComplete);

        self.areAsyncRegistrationsComplete = YES;

        completion();
    }];
}

+ (void)protectFiles
{
    // Protect the entire new database directory.
    [OWSFileSystem protectFileOrFolderAtPath:self.databaseDirPath];
}

+ (NSString *)databaseDirPath
{
    NSString *databaseDirPath = [[OWSFileSystem appSharedDataDirectoryPath] stringByAppendingPathComponent:@"Sessions"];

    if (![OWSFileSystem ensureDirectoryExists:databaseDirPath]) {
        [NSException raise:OWSSessionStorageExceptionName_CouldNotCreateDatabaseDirectory
                    format:@"Could not create new database directory"];
    }
    return databaseDirPath;
}

+ (NSString *)databaseFilename
{
    return @"Sessions.sqlite";
}

+ (NSString *)databaseFilename_SHM
{
    return [self.databaseFilename stringByAppendingString:@"-shm"];
}

+ (NSString *)databaseFilename_WAL
{
    return [self.databaseFilename stringByAppendingString:@"-wal"];
}

+ (NSString *)databaseFilePath
{
    return [self.databaseDirPath stringByAppendingPathComponent:self.databaseFilename];
}

+ (NSString *)databaseFilePath_SHM
{
    return [self.databaseDirPath stringByAppendingPathComponent:self.databaseFilename_SHM];
}

+ (NSString *)databaseFilePath_WAL
{
    return [self.databaseDirPath stringByAppendingPathComponent:self.databaseFilename_WAL];
}

- (NSString *)databaseFilePath
{
    return OWSSessionStorage.databaseFilePath;
}

- (YapDatabaseConnection *)dbConnection
{
    OWSAssert(_dbConnection);

    return _dbConnection;
}

+ (YapDatabaseConnection *)dbConnection
{
    return OWSSessionStorage.sharedManager.dbConnection;
}

#pragma mark - Migration

- (void)migrateCollection:(NSString *)collection fromStorage:(OWSStorage *)storage valueClass:(Class)valueClass
{
    OWSAssert(collection.length > 0);
    OWSAssert(storage);

    DDLogInfo(@"%@: migrating %@", self.logTag, collection);

    NSMutableDictionary<NSString *, id> *collectionContents = [NSMutableDictionary new];

    // 1. Read from old storage.
    [storage.newDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction
            enumerateKeysAndObjectsInCollection:collection
                                     usingBlock:^(NSString *_Nonnull key, id _Nonnull value, BOOL *_Nonnull stop) {
                                         if (![value isKindOfClass:valueClass]) {
                                             OWSFail(
                                                 @"Unexpected type: %@ in collection: %@.", [value class], collection);
                                             return;
                                         }

                                         collectionContents[key] = value;
                                     }];
    }];

    // 2. Write to new storage.
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [collectionContents enumerateKeysAndObjectsUsingBlock:^(NSString *_Nonnull key, id value, BOOL *_Nonnull stop){
        }];
    }];

    DDLogInfo(@"%@ migrated %zd items.", self.logTag, (unsigned long)collectionContents.count);
}

@end

NS_ASSUME_NONNULL_END
