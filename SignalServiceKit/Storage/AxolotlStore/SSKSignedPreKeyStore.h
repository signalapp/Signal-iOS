//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>
#import <SignalServiceKit/OWSIdentity.h>

NS_ASSUME_NONNULL_BEGIN

@class ECKeyPair;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SignedPreKeyRecord;

@interface SSKSignedPreKeyStore : NSObject

- (instancetype)initForIdentity:(OWSIdentity)identity;

#pragma mark - SignedPreKeyStore transactions

- (nullable SignedPreKeyRecord *)loadSignedPreKey:(int)signedPreKeyId transaction:(SDSAnyReadTransaction *)transaction;

- (void)storeSignedPreKey:(int)signedPreKeyId
       signedPreKeyRecord:(SignedPreKeyRecord *)signedPreKeyRecord
              transaction:(SDSAnyWriteTransaction *)transaction;

- (void)removeSignedPreKey:(int)signedPreKeyId transaction:(SDSAnyWriteTransaction *)transaction;

- (void)cullSignedPreKeyRecordsWithJustUploadedSignedPreKey:(SignedPreKeyRecord *)justUploadedSignedPreKey
                                                transaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(cullSignedPreKeyRecords(justUploadedSignedPreKey:transaction:));

#pragma mark -

- (SignedPreKeyRecord *)generateRandomSignedRecord;

#pragma mark - Prekey rotation tracking
- (void)setLastSuccessfulRotationDate:(NSDate *)date transaction:(SDSAnyWriteTransaction *)transaction;
- (nullable NSDate *)getLastSuccessfulRotationDateWithTransaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(getLastSuccessfulRotationDate(transaction:));

#pragma mark - Debugging

#if TESTABLE_BUILD
- (void)removeAll:(SDSAnyWriteTransaction *)transaction;
#endif

@end

NS_ASSUME_NONNULL_END
