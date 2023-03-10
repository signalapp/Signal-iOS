//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ECKeyPair;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SignedPreKeyRecord;

typedef NS_ENUM(uint8_t, OWSIdentity);

@interface SSKSignedPreKeyStore : NSObject

- (instancetype)initForIdentity:(OWSIdentity)identity;

#pragma mark - SignedPreKeyStore transactions

- (nullable SignedPreKeyRecord *)loadSignedPreKey:(int)signedPreKeyId transaction:(SDSAnyReadTransaction *)transaction;

- (NSArray<SignedPreKeyRecord *> *)loadSignedPreKeysWithTransaction:(SDSAnyReadTransaction *)transaction;

- (void)storeSignedPreKey:(int)signedPreKeyId
       signedPreKeyRecord:(SignedPreKeyRecord *)signedPreKeyRecord
              transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)containsSignedPreKey:(int)signedPreKeyId transaction:(SDSAnyReadTransaction *)transaction;

- (void)removeSignedPreKey:(int)signedPreKeyId transaction:(SDSAnyWriteTransaction *)transaction;

- (void)cullSignedPreKeyRecordsWithTransaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(cullSignedPreKeyRecords(transaction:));

#pragma mark -

+ (SignedPreKeyRecord *)generateSignedPreKeySignedWithIdentityKey:(ECKeyPair *)identityKeyPair
    NS_SWIFT_NAME(generateSignedPreKey(signedBy:));
- (SignedPreKeyRecord *)generateRandomSignedRecord;

- (nullable SignedPreKeyRecord *)currentSignedPreKey;
- (nullable SignedPreKeyRecord *)currentSignedPreKeyWithTransaction:(SDSAnyReadTransaction *)transaction;

// Returns nil if no current signed prekey id is found.
- (nullable NSNumber *)currentSignedPrekeyId;
- (void)setCurrentSignedPrekeyId:(int)value transaction:(SDSAnyWriteTransaction *)transaction;

#pragma mark - Prekey update failures

- (int)prekeyUpdateFailureCountWithTransaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(prekeyUpdateFailureCount(transaction:));
- (nullable NSDate *)firstPrekeyUpdateFailureDateWithTransaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(firstPrekeyUpdateFailureDate(transaction:));
- (NSInteger)incrementPrekeyUpdateFailureCountWithTransaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(incrementPrekeyUpdateFailureCount(transaction:));
- (void)clearPrekeyUpdateFailureCountWithTransaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(clearPrekeyUpdateFailureCount(transaction:));

#pragma mark - Debugging

- (void)logSignedPreKeyReport;

#if TESTABLE_BUILD
- (void)removeAll:(SDSAnyWriteTransaction *)transaction;
- (void)setPrekeyUpdateFailureCount:(NSInteger)count
                   firstFailureDate:(NSDate *)firstFailureDate
                        transaction:(SDSAnyWriteTransaction *)transaction;
#endif

@end

NS_ASSUME_NONNULL_END
