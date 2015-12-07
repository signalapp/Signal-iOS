//
//  TSStorageManager+SignedPreKeyStore.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 06/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <AxolotlKit/SignedPreKeyStore.h>
#import "TSStorageManager.h"


#define TSStorageManagerSignedPreKeyStoreCollection @"TSStorageManagerSignedPreKeyStoreCollection"

@interface TSStorageManager (SignedPreKeyStore) <SignedPreKeyStore>

- (SignedPreKeyRecord *)generateRandomSignedRecord;

@end
