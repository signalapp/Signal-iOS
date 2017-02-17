//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <AxolotlKit/SignedPreKeyStore.h>
#import "TSStorageManager.h"

@interface TSStorageManager (SignedPreKeyStore) <SignedPreKeyStore>

- (SignedPreKeyRecord *)generateRandomSignedRecord;

- (nullable SignedPreKeyRecord *)loadSignedPrekeyOrNil:(int)signedPreKeyId;

// Returns nil if no current signed prekey id is found.
- (nullable NSNumber *)currentSignedPrekeyId;
- (void)setCurrentSignedPrekeyId:(int)value;

#pragma mark - Prekey update failures

- (int)prekeyUpdateFailureCount;
- (void)clearPrekeyUpdateFailureCount;
- (int)incrementPrekeyUpdateFailureCount;

- (nullable NSDate *)firstPrekeyUpdateFailureDate;
- (void)setFirstPrekeyUpdateFailureDate:(nonnull NSDate *)value;
- (void)clearFirstPrekeyUpdateFailureDate;

@end
