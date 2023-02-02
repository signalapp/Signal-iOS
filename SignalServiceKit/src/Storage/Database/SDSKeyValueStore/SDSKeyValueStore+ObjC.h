//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SDSKeyValueStore;

/// We can't add an objc category to a Swift base class (SDSKeyValueStore), so instead
/// this class wraps the SDSKeyValueStore.
///
/// We cannot simply add these methods to the base implementation because of the way
/// Swift bridges generics vs. return AnyObject. Essentially, methods which we'd want
/// to sometimes return nil, will instead return NSNull.
/// https://github.com/apple/swift-evolution/blob/master/proposals/0140-bridge-optional-to-nsnull.md
@interface SDSKeyValueStoreObjC : NSObject

- (instancetype)initWithSDSKeyValueStore:(SDSKeyValueStore *)keyValueStore;

- (nullable id)objectForKey:(NSString *)key
             ofExpectedType:(Class)klass
                transaction:(SDSAnyReadTransaction *)transaction;

- (void)setObject:(id)object
    ofExpectedType:(Class)klass
            forKey:(NSString *)key
       transaction:(SDSAnyWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
