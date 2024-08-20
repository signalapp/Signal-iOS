//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Mantle/MTLModel+NSCoding.h>

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyWriteTransaction;
@class SDSDatabaseStorage;

@protocol SDSRecordDelegate

- (void)updateRowId:(int64_t)rowId;

@end

#pragma mark -

// TODO: Rename and/or merge with BaseModel.
@interface TSYapDatabaseObject : MTLModel <SDSRecordDelegate>

+ (NSString *)generateUniqueId;

/**
 *  The unique identifier of the stored object
 */
@property (nonatomic, readonly) NSString *uniqueId;

// This property should only ever be accesssed within a GRDB write transaction.
@property (atomic, readonly, nullable) NSNumber *grdbId;

- (instancetype)init;

/**
 *  Initializes a new database object with a unique identifier
 *
 *  @param uniqueId Key used for the key-value store
 *
 *  @return Initialized object
 */
- (instancetype)initWithUniqueId:(NSString *)uniqueId NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithGrdbId:(int64_t)grdbId uniqueId:(NSString *)uniqueId NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

// These methods should only ever be called within a GRDB write transaction.
- (void)clearRowId;
// This method is used to facilitate a database object replacement. See:
// OWSRecoverableDecryptionPlaceholder.
- (void)replaceRowId:(int64_t)rowId uniqueId:(NSString *)uniqueId;

#pragma mark -

// GRDB TODO: As a perf optimization, we could only call these
//            methods for certain kinds of models which we could
//            detect at compile time.
@property (nonatomic, readonly) BOOL shouldBeSaved;

#pragma mark - Data Store Write Hooks

- (void)anyWillInsertWithTransaction:(SDSAnyWriteTransaction *)transaction;
- (void)anyDidInsertWithTransaction:(SDSAnyWriteTransaction *)transaction;
- (void)anyWillUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction;
- (void)anyDidUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction;
- (void)anyWillRemoveWithTransaction:(SDSAnyWriteTransaction *)transaction;
- (void)anyDidRemoveWithTransaction:(SDSAnyWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
