//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"

NS_ASSUME_NONNULL_BEGIN

void runSyncRegistrationsForPrimaryStorage(OWSStorage *storage);
void runAsyncRegistrationsForPrimaryStorage(OWSStorage *storage);

// TODO: Rename to OWSPrimaryStorage?
@interface TSStorageManager : OWSStorage

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

- (YapDatabaseConnection *)dbReadConnection;
- (YapDatabaseConnection *)dbReadWriteConnection;
+ (YapDatabaseConnection *)dbReadConnection;
+ (YapDatabaseConnection *)dbReadWriteConnection;

+ (NSString *)databaseFilePath;
+ (NSString *)databaseFilePath_SHM;
+ (NSString *)databaseFilePath_WAL;

// This method is used to copy the primary database for the SAE.
- (void)copyPrimaryDatabaseFileWithCompletion:(void (^_Nonnull)(void))completion;

@end

NS_ASSUME_NONNULL_END
