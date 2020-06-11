//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"
#import "SSKEnvironment.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

// This macro is only intended to be used within TSYapDatabaseObject.
#define OWSAssertCanReadYDB()                                                                                          \
    do {                                                                                                               \
        if (!self.databaseStorage.canReadFromYdb) {                                                                    \
            OWSLogError(@"storageMode: %@.", SSKFeatureFlags.storageModeDescription);                                  \
            OWSLogError(                                                                                               \
                @"StorageCoordinatorState: %@.", NSStringFromStorageCoordinatorState(self.storageCoordinator.state));  \
            OWSLogError(@"dataStoreForUI: %@.", NSStringForDataStore(StorageCoordinator.dataStoreForUI));              \
            switch (SSKFeatureFlags.storageModeStrictness) {                                                           \
                case StorageModeStrictnessFail:                                                                        \
                    OWSFail(@"Unexpected YDB read.");                                                                  \
                    break;                                                                                             \
                case StorageModeStrictnessFailDebug:                                                                   \
                    OWSFailDebug(@"Unexpected YDB read.");                                                             \
                    break;                                                                                             \
                case StorageModeStrictnessLog:                                                                         \
                    OWSLogError(@"Unexpected YDB read.");                                                              \
                    break;                                                                                             \
            }                                                                                                          \
        }                                                                                                              \
    } while (NO)

// This macro is only intended to be used within TSYapDatabaseObject.
#define OWSAssertCanWriteYDB()                                                                                         \
    do {                                                                                                               \
        if (!self.databaseStorage.canWriteToYdb) {                                                                     \
            OWSLogError(@"storageMode: %@.", SSKFeatureFlags.storageModeDescription);                                  \
            OWSLogError(                                                                                               \
                @"StorageCoordinatorState: %@.", NSStringFromStorageCoordinatorState(self.storageCoordinator.state));  \
            OWSLogError(@"dataStoreForUI: %@.", NSStringForDataStore(StorageCoordinator.dataStoreForUI));              \
            switch (SSKFeatureFlags.storageModeStrictness) {                                                           \
                case StorageModeStrictnessFail:                                                                        \
                    OWSFail(@"Unexpected YDB write.");                                                                 \
                    break;                                                                                             \
                case StorageModeStrictnessFailDebug:                                                                   \
                    OWSFailDebug(@"Unexpected YDB write.");                                                            \
                    break;                                                                                             \
                case StorageModeStrictnessLog:                                                                         \
                    OWSLogError(@"Unexpected YDB write.");                                                             \
                    break;                                                                                             \
            }                                                                                                          \
        }                                                                                                              \
    } while (NO)

#pragma mark -

@interface TSYapDatabaseObject ()

@property (atomic, nullable) NSNumber *grdbId;

@end

#pragma mark -

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

- (instancetype)initWithGrdbId:(int64_t)grdbId uniqueId:(NSString *)uniqueId
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

    _grdbId = @(grdbId);

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

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

+ (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (StorageCoordinator *)storageCoordinator
{
    return SSKEnvironment.shared.storageCoordinator;
}

+ (StorageCoordinator *)storageCoordinator
{
    return SSKEnvironment.shared.storageCoordinator;
}

+ (NSString *)collection
{
    return NSStringFromClass([self class]);
}

#pragma mark -

- (void)ydb_saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertCanWriteYDB();

    if (!self.shouldBeSaved) {
        OWSLogDebug(@"Skipping save for %@.", [self class]);

        return;
    }

    [transaction setObject:self forKey:self.uniqueId inCollection:[[self class] collection]];
}

- (void)ydb_removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertCanWriteYDB();

    [transaction removeObjectForKey:self.uniqueId inCollection:[[self class] collection]];
}

+ (void)ydb_enumerateCollectionObjectsWithTransaction:(YapDatabaseReadTransaction *)transaction
                                           usingBlock:(void (^)(id object, BOOL *stop))block
{
    OWSAssertCanReadYDB();

    // Ignoring most of the YapDB parameters, and just passing through the ones we usually use.
    void (^yapBlock)(NSString *key, id object, id metadata, BOOL *stop)
        = ^void(NSString *key, id object, id metadata, BOOL *stop) {
              block(object, stop);
          };

    [transaction enumerateRowsInCollection:[self collection] usingBlock:yapBlock];
}

+ (nullable instancetype)ydb_fetchObjectWithUniqueID:(NSString *)uniqueID
                                         transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertCanReadYDB();

    return [transaction objectForKey:uniqueID inCollection:[self collection]];
}

#pragma mark Reload

- (void)ydb_reloadWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertCanReadYDB();

    [self ydb_reloadWithTransaction:transaction ignoreMissing:NO];
}

- (void)ydb_reloadWithTransaction:(YapDatabaseReadTransaction *)transaction ignoreMissing:(BOOL)ignoreMissing
{
    OWSAssertCanReadYDB();

    TSYapDatabaseObject *latest = [[self class] ydb_fetchObjectWithUniqueID:self.uniqueId transaction:transaction];
    if (!latest) {
        if (!ignoreMissing) {
            OWSFailDebug(@"`latest` was unexpectedly nil");
        }
        return;
    }

    [self setValuesForKeysWithDictionary:latest.dictionaryValue];
}

#pragma mark -

- (BOOL)shouldBeSaved
{
    return YES;
}

+ (BOOL)shouldBeIndexedForFTS
{
    return NO;
}

#pragma mark - Write Hooks

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

- (NSString *)transactionFinalizationKey
{
    return [NSString stringWithFormat:@"%@.%@", self.class.collection, self.uniqueId];
}

#pragma mark - SDSRecordDelegate

- (void)updateRowId:(int64_t)rowId
{
    if (self.grdbId != nil) {
        OWSAssertDebug(self.grdbId.longLongValue == rowId);
        OWSFailDebug(@"grdbId set more than once.");
    }
    self.grdbId = @(rowId);
}

- (void)clearRowId
{
    self.grdbId = nil;
}

@end

NS_ASSUME_NONNULL_END
