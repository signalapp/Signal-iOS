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

- (instancetype)initWithUniqueId:(NSString *_Nullable)aUniqueId
{
    self = [super init];
    if (!self) {
        return self;
    }

    _uniqueId = aUniqueId;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    return self;
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
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

- (YapDatabaseConnection *)dbReadConnection
{
    return [[self class] dbReadConnection];
}

- (YapDatabaseConnection *)dbReadWriteConnection
{
    return [[self class] dbReadWriteConnection];
}

- (OWSPrimaryStorage *)primaryStorage
{
    return [[self class] primaryStorage];
}

#pragma mark Class Methods

+ (YapDatabaseConnection *)dbReadConnection
{
    OWSJanksUI();

    // We use TSYapDatabaseObject's dbReadWriteConnection (not OWSPrimaryStorage's
    // dbReadConnection) for consistency, since we tend to [TSYapDatabaseObject
    // save] and want to write to the same connection we read from.  To get true
    // consistency, we'd want to update entities by reading & writing from within
    // the same transaction, but that'll be a big refactor.
    return self.dbReadWriteConnection;
}

+ (YapDatabaseConnection *)dbReadWriteConnection
{
    OWSJanksUI();

    return SSKEnvironment.shared.objectReadWriteConnection;
}

+ (OWSPrimaryStorage *)primaryStorage
{
    return [OWSPrimaryStorage sharedManager];
}

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

#pragma mark - Update With...

- (void)applyChangeToSelfAndLatestCopy:(YapDatabaseReadWriteTransaction *)transaction
                           changeBlock:(void (^)(id))changeBlock
{
    OWSAssertDebug(transaction);

    changeBlock(self);

    NSString *collection = [[self class] collection];
    id latestInstance = [transaction objectForKey:self.uniqueId inCollection:collection];
    if (latestInstance) {
        // Don't apply changeBlock twice to the same instance.
        // It's at least unnecessary and actually wrong for some blocks.
        // e.g. `changeBlock: { $0 in $0.someField++ }`
        if (latestInstance != self) {
            changeBlock(latestInstance);
        }
        [latestInstance saveWithTransaction:transaction];
    }
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

- (BOOL)anyCanBeSaved
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
    return [self enumerateCollectionObjectsWithTransaction:transaction usingBlock:block];
}

+ (nullable instancetype)ydb_fetchObjectWithUniqueID:(NSString *)uniqueID
                                         transaction:(YapDatabaseReadTransaction *)transaction
{
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
    [self reloadWithTransaction:transaction];
}

- (void)ydb_reloadWithTransaction:(YapDatabaseReadTransaction *)transaction ignoreMissing:(BOOL)ignoreMissing
{
    [self reloadWithTransaction:transaction ignoreMissing:ignoreMissing];
}

- (void)ydb_saveAsyncWithCompletionBlock:(void (^_Nullable)(void))completionBlock
{
    [self saveAsyncWithCompletionBlock:completionBlock];
}

- (void)ydb_saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self saveWithTransaction:transaction];
}

- (void)ydb_removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self removeWithTransaction:transaction];
}

- (void)ydb_remove
{
    [self remove];
}

- (void)ydb_applyChangeToSelfAndLatestCopy:(YapDatabaseReadWriteTransaction *)transaction
                               changeBlock:(void (^)(id))changeBlock
{
    [self applyChangeToSelfAndLatestCopy:transaction changeBlock:changeBlock];
}

@end

NS_ASSUME_NONNULL_END
