//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <AxolotlKit/SignedPreKeyStore.h>

NS_ASSUME_NONNULL_BEGIN

@interface SSKSignedPreKeyStore : NSObject <SignedPreKeyStore>

- (SignedPreKeyRecord *)generateRandomSignedRecord;

// Returns nil if no current signed prekey id is found.
- (nullable NSNumber *)currentSignedPrekeyId;
- (void)setCurrentSignedPrekeyId:(int)value;
- (nullable SignedPreKeyRecord *)currentSignedPreKey;

#pragma mark - Prekey update failures

- (int)prekeyUpdateFailureCount;
- (void)clearPrekeyUpdateFailureCount;
- (NSInteger)incrementPrekeyUpdateFailureCount;

- (nullable NSDate *)firstPrekeyUpdateFailureDate;
- (void)setFirstPrekeyUpdateFailureDate:(nonnull NSDate *)value;
- (void)clearFirstPrekeyUpdateFailureDate;

#pragma mark - Debugging

- (void)logSignedPreKeyReport;

@end

NS_ASSUME_NONNULL_END
