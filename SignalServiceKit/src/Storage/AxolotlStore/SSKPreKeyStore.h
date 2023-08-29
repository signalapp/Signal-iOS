//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>
#import <SignalServiceKit/OWSIdentity.h>

NS_ASSUME_NONNULL_BEGIN

@class PreKeyRecord;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SDSKeyValueStore;

@interface SSKPreKeyStore : NSObject

- (instancetype)initForIdentity:(OWSIdentity)identity;

- (NSArray<PreKeyRecord *> *)generatePreKeyRecords;

- (NSArray<PreKeyRecord *> *)generatePreKeyRecordsWithTransaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(generatePreKeyRecords(transaction:));

- (void)storePreKeyRecords:(NSArray<PreKeyRecord *> *)preKeyRecords
               transaction:(SDSAnyWriteTransaction *)transaction NS_SWIFT_NAME(storePreKeyRecords(_:transaction:));

#if TESTABLE_BUILD
- (void)removeAll:(SDSAnyWriteTransaction *)transaction;
#endif

- (nullable PreKeyRecord *)loadPreKey:(int)preKeyId
                          transaction:(SDSAnyReadTransaction *)transaction;

- (void)storePreKey:(int)preKeyId preKeyRecord:(PreKeyRecord *)record
        transaction:(SDSAnyWriteTransaction *)transaction;

- (void)removePreKey:(int)preKeyId
         transaction:(SDSAnyWriteTransaction *)transaction;

- (void)cullPreKeyRecordsWithTransaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(cullPreKeyRecords(transaction:));

@end

NS_ASSUME_NONNULL_END
