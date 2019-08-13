//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface BaseModel : TSYapDatabaseObject

@property (class, nonatomic, readonly) BOOL shouldBeIndexedForFTS;

#pragma mark - YDB Deprecation

// Deprecate all YDB methods.
//
// This will break Swift usage and generate warnings for Obj-C usage.
// Note: this functionality can still be accessed (for example by the
// SDS model extensions) via the ydb_ methods of TSYapDatabaseObject.
+ (NSUInteger)numberOfKeysInCollectionWithTransaction:(YapDatabaseReadTransaction *)transaction NS_UNAVAILABLE;
+ (void)enumerateCollectionObjectsWithTransaction:(YapDatabaseReadTransaction *)transaction
                                       usingBlock:(void (^)(id object, BOOL *stop))block NS_UNAVAILABLE;
+ (nullable instancetype)fetchObjectWithUniqueID:(NSString *)uniqueID
                                     transaction:(YapDatabaseReadTransaction *)transaction NS_UNAVAILABLE;
- (void)reloadWithTransaction:(YapDatabaseReadTransaction *)transaction NS_UNAVAILABLE;
- (void)reloadWithTransaction:(YapDatabaseReadTransaction *)transaction
                ignoreMissing:(BOOL)ignoreMissing NS_UNAVAILABLE;
- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction NS_UNAVAILABLE;
- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
