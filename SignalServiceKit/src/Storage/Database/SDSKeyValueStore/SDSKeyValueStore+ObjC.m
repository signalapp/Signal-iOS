//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "SDSKeyValueStore+ObjC.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface SDSKeyValueStoreObjC ()

@property (nonatomic, readonly) SDSKeyValueStore *keyValueStore;

@end

@implementation SDSKeyValueStoreObjC

- (instancetype)initWithSDSKeyValueStore:(SDSKeyValueStore *)keyValueStore
{
    self = [super init];
    if (!self) {
        return self;
    }

    _keyValueStore = keyValueStore;

    return self;
}

- (nullable id)objectForKey:(NSString *)key ofExpectedType:(Class)klass transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(key.length > 0);

    id _Nullable value = [self.keyValueStore getObjectForKey:key transaction:transaction];

    OWSAssert(!value || [value isKindOfClass:klass]);
    return value;
}

- (void)setObject:(id)object
    ofExpectedType:(Class)klass
            forKey:(NSString *)key
       transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(key.length > 0);
    OWSAssert([object isKindOfClass:klass]);
    [self.keyValueStore setObject:object key:key transaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
