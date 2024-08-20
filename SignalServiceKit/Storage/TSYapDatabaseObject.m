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

+ (NSString *)generateUniqueId
{
    return [[NSUUID UUID] UUIDString];
}

- (instancetype)init
{
    return [self initWithUniqueId:[[self class] generateUniqueId]];
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
        _uniqueId = [[self class] generateUniqueId];
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
        _uniqueId = [[self class] generateUniqueId];
    }

    _grdbId = @(grdbId);

    return self;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
#pragma clang diagnostic pop

    if (!self) {
        return self;
    }

    if (_uniqueId.length < 1) {
        OWSFailDebug(@"Invalid uniqueId.");
        _uniqueId = [[NSUUID UUID] UUIDString];
    }

    return self;
}

#pragma mark -

- (BOOL)shouldBeSaved
{
    return YES;
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
