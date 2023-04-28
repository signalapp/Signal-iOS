//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSYapDatabaseObject.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSYapDatabaseObject ()

@property (nonatomic) NSString *uniqueId;
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

+ (NSString *)collection
{
    return NSStringFromClass([self class]);
}

#pragma mark -

- (BOOL)shouldBeSaved
{
    return YES;
}

+ (TSFTSIndexMode)FTSIndexMode
{
    return TSFTSIndexModeNever;
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

- (void)replaceRowId:(int64_t)rowId uniqueId:(NSString *)uniqueId
{
    self.grdbId = @(rowId);
    self.uniqueId = [uniqueId copy];
}

@end

NS_ASSUME_NONNULL_END
