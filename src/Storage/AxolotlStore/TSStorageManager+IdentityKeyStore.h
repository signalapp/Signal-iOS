//
//  TSStorageManager+IdentityKeyStore.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 06/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <AxolotlKit/IdentityKeyStore.h>
#import "TSStorageManager.h"

@interface TSStorageManager (IdentityKeyStore) <IdentityKeyStore>

- (void)generateNewIdentityKey;
- (NSData *)identityKeyForRecipientId:(NSString *)recipientId;
- (void)removeIdentityKeyForRecipient:(NSString *)receipientId;

@end
