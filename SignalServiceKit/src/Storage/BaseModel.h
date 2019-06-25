//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface BaseModel : TSYapDatabaseObject

#pragma mark - YDB Deprecation

// Deprecate all YDB methods.
//
// This will break Swift usage and generate warnings for Obj-C usage.
// Note: this functionality can still be accessed (for example by the
// SDS model extensions) via the ydb_ methods of TSYapDatabaseObject.
+ (NSUInteger)numberOfKeysInCollection NS_UNAVAILABLE;
+ (NSUInteger)numberOfKeysInCollectionWithTransaction:(YapDatabaseReadTransaction *)transaction NS_UNAVAILABLE;
+ (void)removeAllObjectsInCollection NS_UNAVAILABLE;
+ (NSArray *)allObjectsInCollection NS_UNAVAILABLE;
+ (void)enumerateCollectionObjectsUsingBlock:(void (^)(id obj, BOOL *stop))block NS_UNAVAILABLE;
+ (void)enumerateCollectionObjectsWithTransaction:(YapDatabaseReadTransaction *)transaction
                                       usingBlock:(void (^)(id object, BOOL *stop))block NS_UNAVAILABLE;
- (YapDatabaseConnection *)dbReadConnection NS_UNAVAILABLE;
+ (YapDatabaseConnection *)dbReadConnection NS_UNAVAILABLE;
- (YapDatabaseConnection *)dbReadWriteConnection NS_UNAVAILABLE;
+ (YapDatabaseConnection *)dbReadWriteConnection NS_UNAVAILABLE;
- (OWSPrimaryStorage *)primaryStorage NS_UNAVAILABLE;
+ (OWSPrimaryStorage *)primaryStorage NS_UNAVAILABLE;
+ (nullable instancetype)fetchObjectWithUniqueID:(NSString *)uniqueID
                                     transaction:(YapDatabaseReadTransaction *)transaction NS_UNAVAILABLE;
+ (nullable instancetype)fetchObjectWithUniqueID:(NSString *)uniqueID NS_UNAVAILABLE;
- (void)save NS_UNAVAILABLE;
- (void)reload NS_UNAVAILABLE;
- (void)reloadWithTransaction:(YapDatabaseReadTransaction *)transaction NS_UNAVAILABLE;
- (void)reloadWithTransaction:(YapDatabaseReadTransaction *)transaction
                ignoreMissing:(BOOL)ignoreMissing NS_UNAVAILABLE;
- (void)saveAsyncWithCompletionBlock:(void (^_Nullable)(void))completionBlock NS_UNAVAILABLE;
- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction NS_UNAVAILABLE;
- (void)touch NS_UNAVAILABLE;
- (void)touchWithTransaction:(YapDatabaseReadWriteTransaction *)transaction NS_UNAVAILABLE;
- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction NS_UNAVAILABLE;
- (void)remove NS_UNAVAILABLE;
- (void)applyChangeToSelfAndLatestCopy:(YapDatabaseReadWriteTransaction *)transaction
                           changeBlock:(void (^)(id))changeBlock NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
