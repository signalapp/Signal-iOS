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

- (void)encodeIdsWithCoder:(NSCoder *)coder
{
    NSNumber *grdbId = self.grdbId;
    if (grdbId != nil) {
        [coder encodeObject:grdbId forKey:@"grdbId"];
    }
    NSString *uniqueId = self.uniqueId;
    if (uniqueId != nil) {
        [coder encodeObject:uniqueId forKey:@"uniqueId"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self) {
        return self;
    }
    self->_grdbId = [coder decodeObjectOfClass:[NSNumber class] forKey:@"grdbId"];
    self->_uniqueId = [coder decodeObjectOfClass:[NSString class] forKey:@"uniqueId"];

    if (_uniqueId.length < 1) {
        OWSFailDebug(@"Invalid uniqueId.");
        _uniqueId = [[NSUUID UUID] UUIDString];
    }

    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = 0;
    result ^= self.grdbId.hash;
    result ^= self.uniqueId.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![other isMemberOfClass:self.class]) {
        return NO;
    }
    TSYapDatabaseObject *typedOther = (TSYapDatabaseObject *)other;
    if (![NSObject isObject:self.grdbId equalToObject:typedOther.grdbId]) {
        return NO;
    }
    if (![NSObject isObject:self.uniqueId equalToObject:typedOther.uniqueId]) {
        return NO;
    }
    return YES;
}

- (id)copyAndAssignIdsWithZone:(nullable NSZone *)zone
{
    TSYapDatabaseObject *result = [[[self class] allocWithZone:zone] init];
    result->_grdbId = self.grdbId;
    result->_uniqueId = self.uniqueId;
    return result;
}

#pragma mark -

- (BOOL)shouldBeSaved
{
    return YES;
}

#pragma mark - Write Hooks

- (void)anyWillInsertWithTransaction:(DBWriteTransaction *)transaction
{
    // Do nothing.
}

- (void)anyDidInsertWithTransaction:(DBWriteTransaction *)transaction
{
    // Do nothing.
}

- (void)anyWillUpdateWithTransaction:(DBWriteTransaction *)transaction
{
    // Do nothing.
}

- (void)anyDidUpdateWithTransaction:(DBWriteTransaction *)transaction
{
    // Do nothing.
}

- (void)anyWillRemoveWithTransaction:(DBWriteTransaction *)transaction
{
    // Do nothing.
}

- (void)anyDidRemoveWithTransaction:(DBWriteTransaction *)transaction
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
