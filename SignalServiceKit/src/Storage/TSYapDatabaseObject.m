//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"
#import "OWSPrimaryStorage.h"
#import "SSKEnvironment.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

@implementation TSYapDatabaseObject

- (instancetype)init
{
    return [self initWithUniqueId:[[NSUUID UUID] UUIDString]];
}

- (instancetype)initWithUniqueId:(NSString *)uniqueId
{
    self = [super init];
    if (!self) {
        return self;
    }

    if (uniqueId.length > 0) {
        _uniqueId = uniqueId;
    } else {
        OWSFailDebug(@"Invalid uniqueId.");
        _uniqueId = [[NSUUID UUID] UUIDString];
    }

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (_uniqueId.length < 1) {
        OWSFailDebug(@"Invalid uniqueId.");
        _uniqueId = [[NSUUID UUID] UUIDString];
    }

    return self;
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!self.shouldBeSaved) {
        OWSLogDebug(@"Skipping save for %@.", [self class]);

        return;
    }

    [transaction setObject:self forKey:self.uniqueId inCollection:[[self class] collection]];
}

- (void)save
{
    [[self dbReadWriteConnection] readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self saveWithTransaction:transaction];
    }];
}

- (void)saveAsyncWithCompletionBlock:(void (^_Nullable)(void))completionBlock
{
    [[self dbReadWriteConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [self saveWithTransaction:transaction];
    }
                                          completionBlock:completionBlock];
}

- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [transaction removeObjectForKey:self.uniqueId inCollection:[[self class] collection]];
}

- (void)remove
{
    [[self dbReadWriteConnection] readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self removeWithTransaction:transaction];
    }];
}

#pragma mark Class Methods

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

+ (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

+ (NSString *)collection
{
    return NSStringFromClass([self class]);
}

+ (NSUInteger)numberOfKeysInCollection
{
    __block NSUInteger count;
    [[self dbReadConnection] readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        count = [self numberOfKeysInCollectionWithTransaction:transaction];
    }];
    return count;
}

+ (NSUInteger)numberOfKeysInCollectionWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    return [transaction numberOfKeysInCollection:[self collection]];
}

+ (NSArray *)allObjectsInCollection
{
    __block NSMutableArray *all = [[NSMutableArray alloc] initWithCapacity:[self numberOfKeysInCollection]];
    [self enumerateCollectionObjectsUsingBlock:^(id object, BOOL *stop) {
        [all addObject:object];
    }];
    return [all copy];
}

+ (void)enumerateCollectionObjectsUsingBlock:(void (^)(id object, BOOL *stop))block
{
    [[self dbReadConnection] readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self enumerateCollectionObjectsWithTransaction:transaction usingBlock:block];
    }];
}

+ (void)enumerateCollectionObjectsWithTransaction:(YapDatabaseReadTransaction *)transaction
                                       usingBlock:(void (^)(id object, BOOL *stop))block
{
    // Ignoring most of the YapDB parameters, and just passing through the ones we usually use.
    void (^yapBlock)(NSString *key, id object, id metadata, BOOL *stop)
        = ^void(NSString *key, id object, id metadata, BOOL *stop) {
              block(object, stop);
          };

    [transaction enumerateRowsInCollection:[self collection] usingBlock:yapBlock];
}

+ (void)removeAllObjectsInCollection
{
    [[self dbReadWriteConnection] readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeAllObjectsInCollection:[self collection]];
    }];
}

+ (nullable instancetype)fetchObjectWithUniqueID:(NSString *)uniqueID
                                     transaction:(YapDatabaseReadTransaction *)transaction
{
    return [transaction objectForKey:uniqueID inCollection:[self collection]];
}

+ (nullable instancetype)fetchObjectWithUniqueID:(NSString *)uniqueID
{
    __block id _Nullable object = nil;
    [[self dbReadConnection] readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        object = [transaction objectForKey:uniqueID inCollection:[self collection]];
    }];
    return object;
}

#pragma mark Reload

- (void)reload
{
    [self.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        [self reloadWithTransaction:transaction];
    }];
}

- (void)reloadWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    [self reloadWithTransaction:transaction ignoreMissing:NO];
}

- (void)reloadWithTransaction:(YapDatabaseReadTransaction *)transaction ignoreMissing:(BOOL)ignoreMissing
{
    TSYapDatabaseObject *latest = [[self class] fetchObjectWithUniqueID:self.uniqueId transaction:transaction];
    if (!latest) {
        if (!ignoreMissing) {
            OWSFailDebug(@"`latest` was unexpectedly nil");
        }
        return;
    }

    [self setValuesForKeysWithDictionary:latest.dictionaryValue];
}

#pragma mark - Write Hooks

- (BOOL)shouldBeSaved
{
    return YES;
}

- (void)anyWillInsertWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    // Do nothing.
}

- (void)anyDidInsertWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    // Do nothing.
}

- (void)anyWillUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    // Do nothing.
}

- (void)anyDidUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    // Do nothing.
}

- (void)anyWillRemoveWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    // Do nothing.
}

- (void)anyDidRemoveWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    // Do nothing.
}

#pragma mark - YDB Deprecation

+ (NSUInteger)ydb_numberOfKeysInCollection
{
    return [self numberOfKeysInCollection];
}

+ (NSUInteger)ydb_numberOfKeysInCollectionWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    return [self numberOfKeysInCollectionWithTransaction:transaction];
}

+ (void)ydb_removeAllObjectsInCollection
{
    [self removeAllObjectsInCollection];
}

+ (NSArray *)ydb_allObjectsInCollection
{
    return [self allObjectsInCollection];
}

+ (void)ydb_enumerateCollectionObjectsUsingBlock:(void (^)(id obj, BOOL *stop))block
{
    return [self enumerateCollectionObjectsUsingBlock:block];
}

+ (void)ydb_enumerateCollectionObjectsWithTransaction:(YapDatabaseReadTransaction *)transaction
                                           usingBlock:(void (^)(id object, BOOL *stop))block
{
    OWSAssertDebug(transaction);

    return [self enumerateCollectionObjectsWithTransaction:transaction usingBlock:block];
}

+ (nullable instancetype)ydb_fetchObjectWithUniqueID:(NSString *)uniqueID
                                         transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    return [self fetchObjectWithUniqueID:uniqueID transaction:transaction];
}

+ (nullable instancetype)ydb_fetchObjectWithUniqueID:(NSString *)uniqueID
{
    return [self fetchObjectWithUniqueID:uniqueID];
}

- (void)ydb_save
{
    [self save];
}

- (void)ydb_reload
{
    [self reload];
}

- (void)ydb_reloadWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    [self reloadWithTransaction:transaction];
}

- (void)ydb_reloadWithTransaction:(YapDatabaseReadTransaction *)transaction ignoreMissing:(BOOL)ignoreMissing
{
    OWSAssertDebug(transaction);

    [self reloadWithTransaction:transaction ignoreMissing:ignoreMissing];
}

- (void)ydb_saveAsyncWithCompletionBlock:(void (^_Nullable)(void))completionBlock
{
    [self saveAsyncWithCompletionBlock:completionBlock];
}

- (void)ydb_saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    [self saveWithTransaction:transaction];
}

- (void)ydb_removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    [self removeWithTransaction:transaction];
}

- (void)ydb_remove
{
    [self remove];
}

@end

NS_ASSUME_NONNULL_END
