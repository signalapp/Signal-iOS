//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSPrimaryStorage.h"
#import <AxolotlKit/SignedPreKeyStore.h>

NS_ASSUME_NONNULL_BEGIN

// Used for testing
extern NSString *const OWSPrimaryStorageSignedPreKeyStoreCollection;

@interface OWSPrimaryStorage (SignedPreKeyStore) <SignedPreKeyStore>

- (SignedPreKeyRecord *)generateRandomSignedRecord;

- (nullable SignedPreKeyRecord *)loadSignedPrekeyOrNil:(int)signedPreKeyId;

// Returns nil if no current signed prekey id is found.
- (nullable NSNumber *)currentSignedPrekeyId;
- (void)setCurrentSignedPrekeyId:(int)value;
- (nullable SignedPreKeyRecord *)currentSignedPreKey;

#pragma mark - Prekey update failures

- (int)prekeyUpdateFailureCount;
- (void)clearPrekeyUpdateFailureCount;
- (int)incrementPrekeyUpdateFailureCount;

- (nullable NSDate *)firstPrekeyUpdateFailureDate;
- (void)setFirstPrekeyUpdateFailureDate:(nonnull NSDate *)value;
- (void)clearFirstPrekeyUpdateFailureDate;

#pragma mark - Debugging

- (void)logSignedPreKeyReport;

@end

NS_ASSUME_NONNULL_END
