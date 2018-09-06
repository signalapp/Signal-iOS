//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "YapDatabaseConnection+OWS.h"
#import <AxolotlKit/PreKeyRecord.h>
#import <AxolotlKit/SignedPrekeyRecord.h>
#import <Curve25519Kit/Curve25519.h>
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

@implementation YapDatabaseConnection (OWS)

- (BOOL)hasObjectForKey:(NSString *)key inCollection:(NSString *)collection
{
    OWSAssertDebug(key.length > 0);
    OWSAssertDebug(collection.length > 0);

    return nil != [self objectForKey:key inCollection:collection];
}

- (nullable id)objectForKey:(NSString *)key inCollection:(NSString *)collection
{
    OWSAssertDebug(key.length > 0);
    OWSAssertDebug(collection.length > 0);

    __block NSString *_Nullable object;

    [self readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        object = [transaction objectForKey:key inCollection:collection];
    }];

    return object;
}

- (nullable id)objectForKey:(NSString *)key inCollection:(NSString *)collection ofExpectedType:(Class)class
{
    id _Nullable value = [self objectForKey:key inCollection:collection];
    OWSAssertDebug(!value || [value isKindOfClass:class]);
    return value;
}

- (nullable NSDictionary *)dictionaryForKey:(NSString *)key inCollection:(NSString *)collection
{
    return [self objectForKey:key inCollection:collection ofExpectedType:[NSDictionary class]];
}

- (nullable NSString *)stringForKey:(NSString *)key inCollection:(NSString *)collection
{
    return [self objectForKey:key inCollection:collection ofExpectedType:[NSString class]];
}

- (BOOL)boolForKey:(NSString *)key inCollection:(NSString *)collection
{
    return [self boolForKey:key inCollection:collection defaultValue:NO];
}

- (BOOL)boolForKey:(NSString *)key inCollection:(NSString *)collection defaultValue:(BOOL)defaultValue
{
    NSNumber *_Nullable value = [self objectForKey:key inCollection:collection ofExpectedType:[NSNumber class]];
    return value ? [value boolValue] : defaultValue;
}

- (double)doubleForKey:(NSString *)key inCollection:(NSString *)collection defaultValue:(double)defaultValue
{
    NSNumber *_Nullable value = [self objectForKey:key inCollection:collection ofExpectedType:[NSNumber class]];
    return value ? [value doubleValue] : defaultValue;
}

- (nullable NSData *)dataForKey:(NSString *)key inCollection:(NSString *)collection
{
    return [self objectForKey:key inCollection:collection ofExpectedType:[NSData class]];
}

- (nullable ECKeyPair *)keyPairForKey:(NSString *)key inCollection:(NSString *)collection
{
    return [self objectForKey:key inCollection:collection ofExpectedType:[ECKeyPair class]];
}

- (nullable PreKeyRecord *)preKeyRecordForKey:(NSString *)key inCollection:(NSString *)collection
{
    return [self objectForKey:key inCollection:collection ofExpectedType:[PreKeyRecord class]];
}

- (nullable SignedPreKeyRecord *)signedPreKeyRecordForKey:(NSString *)key inCollection:(NSString *)collection
{
    return [self objectForKey:key inCollection:collection ofExpectedType:[SignedPreKeyRecord class]];
}

- (int)intForKey:(NSString *)key inCollection:(NSString *)collection
{
    NSNumber *_Nullable number = [self objectForKey:key inCollection:collection ofExpectedType:[NSNumber class]];
    return [number intValue];
}

- (nullable NSDate *)dateForKey:(NSString *)key inCollection:(NSString *)collection
{
    NSNumber *_Nullable value = [self objectForKey:key inCollection:collection ofExpectedType:[NSNumber class]];
    if (value) {
        return [NSDate dateWithTimeIntervalSince1970:value.doubleValue];
    } else {
        return nil;
    }
}

#pragma mark -

- (NSUInteger)numberOfKeysInCollection:(NSString *)collection
{
    __block NSUInteger result;
    [self readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        result = [transaction numberOfKeysInCollection:collection];
    }];
    return result;
}

- (void)purgeCollection:(NSString *)collection
{
    [self readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeAllObjectsInCollection:collection];
    }];
}

- (void)setObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection
{
    OWSAssertDebug(key.length > 0);
    OWSAssertDebug(collection.length > 0);

    [self readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:object forKey:key inCollection:collection];
    }];
}

- (void)setBool:(BOOL)value forKey:(NSString *)key inCollection:(NSString *)collection
{
    OWSAssertDebug(key.length > 0);
    OWSAssertDebug(collection.length > 0);

    [self setObject:@(value) forKey:key inCollection:collection];
}

- (void)setDouble:(double)value forKey:(NSString *)key inCollection:(NSString *)collection
{
    OWSAssertDebug(key.length > 0);
    OWSAssertDebug(collection.length > 0);

    [self setObject:@(value) forKey:key inCollection:collection];
}

- (void)removeObjectForKey:(NSString *)key inCollection:(NSString *)collection
{
    OWSAssertDebug(key.length > 0);
    OWSAssertDebug(collection.length > 0);

    [self readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeObjectForKey:key inCollection:collection];
    }];
}

- (void)setInt:(int)value forKey:(NSString *)key inCollection:(NSString *)collection
{
    OWSAssertDebug(key.length > 0);
    OWSAssertDebug(collection.length > 0);

    [self setObject:@(value) forKey:key inCollection:collection];
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
