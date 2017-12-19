//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSSessionStorage.h"
#import "OWSFileSystem.h"
#import "OWSStorage+Subclass.h"
#import "TSDatabaseView.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSSessionStorageExceptionName_CouldNotCreateDatabaseDirectory
    = @"OWSSessionStorageExceptionName_CouldNotCreateDatabaseDirectory";

#pragma mark -

@interface OWSSessionStorage ()

@property (nonatomic, readonly) YapDatabaseConnection *dbReadConnection;
@property (nonatomic, readonly) YapDatabaseConnection *dbReadWriteConnection;

@property (atomic) BOOL areAsyncRegistrationsComplete;
@property (atomic) BOOL areSyncRegistrationsComplete;

@end

#pragma mark -

@implementation OWSSessionStorage

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
        _dbReadConnection = self.newDatabaseConnection;
        _dbReadWriteConnection = self.newDatabaseConnection;

        OWSSingletonAssert();
    }

    return self;
}

- (StorageType)storageType
{
    return StorageType_Primary;
}

- (void)resetStorage
{
    _dbReadConnection = nil;
    _dbReadWriteConnection = nil;

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

+ (void)migrateToSharedData
{
    OWSFail(@"TODO");
}

- (NSString *)databaseFilePath
{
    return OWSSessionStorage.databaseFilePath;
}

+ (YapDatabaseConnection *)dbReadConnection
{
    return OWSSessionStorage.sharedManager.dbReadConnection;
}

+ (YapDatabaseConnection *)dbReadWriteConnection
{
    return OWSSessionStorage.sharedManager.dbReadWriteConnection;
}

@end

NS_ASSUME_NONNULL_END
