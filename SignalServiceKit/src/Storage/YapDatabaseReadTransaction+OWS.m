//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "YapDatabaseReadTransaction+OWS.h"
#import <AxolotlKit/PreKeyRecord.h>
#import <AxolotlKit/SignedPrekeyRecord.h>
#import <Curve25519Kit/Curve25519.h>

NS_ASSUME_NONNULL_BEGIN

@implementation YapDatabaseReadTransaction (OWS)

- (nullable id)objectForKey:(NSString *)key inCollection:(NSString *)collection ofExpectedType:(Class) class {
    OWSAssert(key.length > 0);
    OWSAssert(collection.length > 0);

    id _Nullable value = [self objectForKey:key inCollection:collection];
    OWSAssert(!value || [value isKindOfClass:class]);
    return value;
}

    - (nullable NSDictionary *)dictionaryForKey : (NSString *)key inCollection : (NSString *)collection
{
    OWSAssert(key.length > 0);
    OWSAssert(collection.length > 0);

    return [self objectForKey:key inCollection:collection ofExpectedType:[NSDictionary class]];
}

- (nullable NSString *)stringForKey:(NSString *)key inCollection:(NSString *)collection
{
    OWSAssert(key.length > 0);
    OWSAssert(collection.length > 0);

    return [self objectForKey:key inCollection:collection ofExpectedType:[NSString class]];
}

- (BOOL)boolForKey:(NSString *)key inCollection:(NSString *)collection
{
    OWSAssert(key.length > 0);
    OWSAssert(collection.length > 0);

    return [self boolForKey:key inCollection:collection defaultValue:NO];
}

- (BOOL)boolForKey:(NSString *)key inCollection:(NSString *)collection defaultValue:(BOOL)defaultValue
{
    OWSAssert(key.length > 0);
    OWSAssert(collection.length > 0);

    NSNumber *_Nullable value = [self objectForKey:key inCollection:collection ofExpectedType:[NSNumber class]];
    return value ? [value boolValue] : defaultValue;
}

- (nullable NSData *)dataForKey:(NSString *)key inCollection:(NSString *)collection
{
    OWSAssert(key.length > 0);
    OWSAssert(collection.length > 0);

    return [self objectForKey:key inCollection:collection ofExpectedType:[NSData class]];
}

- (nullable ECKeyPair *)keyPairForKey:(NSString *)key inCollection:(NSString *)collection
{
    OWSAssert(key.length > 0);
    OWSAssert(collection.length > 0);

    return [self objectForKey:key inCollection:collection ofExpectedType:[ECKeyPair class]];
}

- (nullable PreKeyRecord *)preKeyRecordForKey:(NSString *)key inCollection:(NSString *)collection
{
    OWSAssert(key.length > 0);
    OWSAssert(collection.length > 0);

    return [self objectForKey:key inCollection:collection ofExpectedType:[PreKeyRecord class]];
}

- (nullable SignedPreKeyRecord *)signedPreKeyRecordForKey:(NSString *)key inCollection:(NSString *)collection
{
    OWSAssert(key.length > 0);
    OWSAssert(collection.length > 0);

    return [self objectForKey:key inCollection:collection ofExpectedType:[SignedPreKeyRecord class]];
}

- (int)intForKey:(NSString *)key inCollection:(NSString *)collection
{
    OWSAssert(key.length > 0);
    OWSAssert(collection.length > 0);

    NSNumber *_Nullable number = [self objectForKey:key inCollection:collection ofExpectedType:[NSNumber class]];
    return [number intValue];
}

- (nullable NSDate *)dateForKey:(NSString *)key inCollection:(NSString *)collection
{
    OWSAssert(key.length > 0);
    OWSAssert(collection.length > 0);

    NSNumber *_Nullable value = [self objectForKey:key inCollection:collection ofExpectedType:[NSNumber class]];
    if (value) {
        return [NSDate dateWithTimeIntervalSince1970:value.doubleValue];
    } else {
        return nil;
    }
}

@end

NS_ASSUME_NONNULL_END
