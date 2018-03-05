//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//
#import "OWSPrimaryStorage.h"
#import "OWSStorage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSBackupStorage : OWSStorage

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initStorage NS_UNAVAILABLE;

- (instancetype)initBackupStorageWithdatabaseDirPath:(NSString *)databaseDirPath
                                     databaseKeySpec:(NSData *)databaseKeySpec NS_DESIGNATED_INITIALIZER;

- (YapDatabaseConnection *)dbConnection;

@end

NS_ASSUME_NONNULL_END
