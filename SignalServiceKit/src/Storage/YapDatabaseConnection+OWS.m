//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "YapDatabaseConnection+OWS.h"
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

@implementation YapDatabaseConnection (OWS)

- (id)objectForKey:(NSString *)key inCollection:(NSString *)collection
{
    __block NSString *object;

    [self readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        object = [transaction objectForKey:key inCollection:collection];
    }];

    return object;
}

- (nullable NSDictionary *)dictionaryForKey:(NSString *)key inCollection:(NSString *)collection
{
    __block NSDictionary *object;

    [self readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        object = [transaction objectForKey:key inCollection:collection];
    }];

    return object;
}

- (nullable NSString *)stringForKey:(NSString *)key inCollection:(NSString *)collection
{
    NSString *string = [self objectForKey:key inCollection:collection];

    return string;
}

- (BOOL)boolForKey:(NSString *)key inCollection:(NSString *)collection
{
    NSNumber *boolNum = [self objectForKey:key inCollection:collection];

    return [boolNum boolValue];
}

- (nullable NSData *)dataForKey:(NSString *)key inCollection:(NSString *)collection
{
    NSData *data = [self objectForKey:key inCollection:collection];
    return data;
}

- (nullable ECKeyPair *)keyPairForKey:(NSString *)key inCollection:(NSString *)collection
{
    ECKeyPair *keyPair = [self objectForKey:key inCollection:collection];

    return keyPair;
}

- (nullable PreKeyRecord *)preKeyRecordForKey:(NSString *)key inCollection:(NSString *)collection
{
    PreKeyRecord *preKeyRecord = [self objectForKey:key inCollection:collection];

    return preKeyRecord;
}

- (nullable SignedPreKeyRecord *)signedPreKeyRecordForKey:(NSString *)key inCollection:(NSString *)collection
{
    SignedPreKeyRecord *preKeyRecord = [self objectForKey:key inCollection:collection];

    return preKeyRecord;
}

- (int)intForKey:(NSString *)key inCollection:(NSString *)collection
{
    int integer = [[self objectForKey:key inCollection:collection] intValue];

    return integer;
}

- (nullable NSDate *)dateForKey:(NSString *)key inCollection:(NSString *)collection
{
    NSNumber *value = [self objectForKey:key inCollection:collection];
    if (value) {
        return [NSDate dateWithTimeIntervalSince1970:value.doubleValue];
    } else {
        return nil;
    }
}

#pragma mark -

- (void)purgeCollection:(NSString *)collection
{
    [self readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeAllObjectsInCollection:collection];
    }];
}

- (void)setObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection
{
    [self readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:object forKey:key inCollection:collection];
    }];
}

- (void)removeObjectForKey:(NSString *)string inCollection:(NSString *)collection
{
    [self readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeObjectForKey:string inCollection:collection];
    }];
}

- (void)setInt:(int)integer forKey:(NSString *)key inCollection:(NSString *)collection
{
    [self setObject:[NSNumber numberWithInt:integer] forKey:key inCollection:collection];
}

- (int)incrementIntForKey:(NSString *)key inCollection:(NSString *)collection
{
    __block int value = 0;
    [self readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        value = [[transaction objectForKey:key inCollection:collection] intValue];
        value++;
        [transaction setObject:@(value) forKey:key inCollection:collection];
    }];
    return value;
}

- (void)setDate:(NSDate *)value forKey:(NSString *)key inCollection:(NSString *)collection
{
    [self setObject:@(value.timeIntervalSince1970) forKey:key inCollection:collection];
}

@end

NS_ASSUME_NONNULL_END
