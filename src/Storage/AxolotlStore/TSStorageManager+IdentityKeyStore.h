//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <AxolotlKit/IdentityKeyStore.h>
#import "TSStorageManager.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const TSStorageManagerTrustedKeysCollection;

@interface TSStorageManager (IdentityKeyStore) <IdentityKeyStore>

/**
 * Explicitly mark an identity as approved for blocking/nonblocking use
 * e.g. in response to a user confirmation action.
 */
- (BOOL)saveRemoteIdentity:(NSData *)identityKey
               recipientId:(NSString *)recipientId
    approvedForBlockingUse:(BOOL)approvedForBlockingUse
 approvedForNonBlockingUse:(BOOL)approvedForNonBlockingUse;

- (void)generateNewIdentityKey;
- (nullable NSData *)identityKeyForRecipientId:(NSString *)recipientId;
- (void)removeIdentityKeyForRecipient:(NSString *)receipientId;

@end

NS_ASSUME_NONNULL_END
