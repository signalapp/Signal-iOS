//
//  TSPrekeyManager.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 07/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSPreKeyManager.h"
#import "TSStorageManager.h"
#import "TSStorageManager+PreKeyStore.h"
#import "TSStorageManager+SignedPreKeyStore.h"
#import "TSStorageManager+IdentityKeyStore.h"
#import "TSNetworkManager.h"
#import "TSRegisterPrekeysRequest.h"

@implementation TSPreKeyManager

+ (void)registerPreKeysWithSuccess:(successCompletionBlock)success failure:(failedVerificationBlock)failureBlock{
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    ECKeyPair *identityKeyPair       = [storageManager identityKeyPair];
    
    if (!identityKeyPair) {
        [storageManager generateNewIdentityKey];
        identityKeyPair = [storageManager identityKeyPair];
    }
    
    PreKeyRecord *lastResortPreKey   = [storageManager getOrGenerateLastResortKey];
    SignedPreKeyRecord *signedPreKey = [storageManager generateRandomSignedRecord];
    
    NSArray *preKeys = [storageManager generatePreKeyRecords];
    
    TSRegisterPrekeysRequest *request = [[TSRegisterPrekeysRequest alloc] initWithPrekeyArray:preKeys
                                                                                  identityKey:[storageManager identityKeyPair].publicKey
                                                                           signedPreKeyRecord:signedPreKey
                                                                             preKeyLastResort:lastResortPreKey];
    
    [[TSNetworkManager sharedManager] queueAuthenticatedRequest:request success:^(NSURLSessionDataTask *task, id responseObject) {
        [storageManager storePreKeyRecords:preKeys];
        [storageManager storeSignedPreKey:signedPreKey.Id signedPreKeyRecord:signedPreKey];
        
        success();
        
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        failureBlock(kTSRegistrationFailureNetwork);
    }];
    
}

@end
