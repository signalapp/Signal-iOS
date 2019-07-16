//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSStorage;
@class YapDatabaseReadTransaction;

@interface OWSIncompleteCallsJob : NSObject

- (void)run;

+ (NSArray<NSString *> *)ydb_incompleteCallIdsWithTransaction:(YapDatabaseReadTransaction *)transaction;

+ (NSString *)databaseExtensionName;
+ (void)asyncRegisterDatabaseExtensionsWithPrimaryStorage:(OWSStorage *)storage;

#ifdef DEBUG
/**
 * Only use the sync version for testing, generally we'll want to register extensions async
 */
- (void)blockingRegisterDatabaseExtensions;
#endif

@end

NS_ASSUME_NONNULL_END
