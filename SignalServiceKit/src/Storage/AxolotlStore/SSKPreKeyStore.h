//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PreKeyRecord;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SDSKeyValueStore;

typedef NS_ENUM(uint8_t, OWSIdentity);

@interface SSKPreKeyStore : NSObject

- (instancetype)initForIdentity:(OWSIdentity)identity;

@property (nonatomic, readonly) SDSKeyValueStore *keyStore;

- (NSArray<PreKeyRecord *> *)generatePreKeyRecords;
- (void)storePreKeyRecords:(NSArray<PreKeyRecord *> *)preKeyRecords NS_SWIFT_NAME(storePreKeyRecords(_:));

#if TESTABLE_BUILD
- (void)removeAll:(SDSAnyWriteTransaction *)transaction;
#endif

- (nullable PreKeyRecord *)loadPreKey:(int)preKeyId
                          transaction:(SDSAnyReadTransaction *)transaction;

- (void)storePreKey:(int)preKeyId preKeyRecord:(PreKeyRecord *)record
        transaction:(SDSAnyWriteTransaction *)transaction;

- (void)removePreKey:(int)preKeyId
         transaction:(SDSAnyWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
