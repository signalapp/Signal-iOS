//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//
#import "OWSPrimaryStorage.h"
#import "OWSStorage.h"

NS_ASSUME_NONNULL_BEGIN

typedef NSData *_Nullable (^BackupStorageKeySpecBlock)(void);

@interface OWSBackupStorage : OWSStorage

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initStorage NS_UNAVAILABLE;

- (instancetype)initBackupStorageWithDatabaseDirPath:(NSString *)databaseDirPath
                                        keySpecBlock:(BackupStorageKeySpecBlock)keySpecBlock NS_DESIGNATED_INITIALIZER;

- (YapDatabaseConnection *)dbConnection;

- (void)logFileSizes;

- (void)runSyncRegistrations;
- (void)runAsyncRegistrationsWithCompletion:(void (^_Nonnull)(void))completion;
- (BOOL)areAllRegistrationsComplete;

- (NSString *)databaseFilePath;
- (NSString *)databaseFilePath_SHM;
- (NSString *)databaseFilePath_WAL;

@end

NS_ASSUME_NONNULL_END
