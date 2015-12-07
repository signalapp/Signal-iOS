//
//  TSPrekeyManager.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 07/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSPreKeyManager.h"

#import "NSURLSessionDataTask+StatusCode.h"
#import "TSNetworkManager.h"
#import "TSStorageHeaders.h"

#define EPHEMERAL_PREKEYS_MINIMUM 15

@implementation TSPreKeyManager

+ (void)registerPreKeysWithSuccess:(successCompletionBlock)success failure:(failedBlock)failureBlock {
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    ECKeyPair *identityKeyPair       = [storageManager identityKeyPair];

    if (!identityKeyPair) {
        [storageManager generateNewIdentityKey];
        identityKeyPair = [storageManager identityKeyPair];
    }

    PreKeyRecord *lastResortPreKey   = [storageManager getOrGenerateLastResortKey];
    SignedPreKeyRecord *signedPreKey = [storageManager generateRandomSignedRecord];

    NSArray *preKeys = [storageManager generatePreKeyRecords];

    TSRegisterPrekeysRequest *request =
        [[TSRegisterPrekeysRequest alloc] initWithPrekeyArray:preKeys
                                                  identityKey:[storageManager identityKeyPair].publicKey
                                           signedPreKeyRecord:signedPreKey
                                             preKeyLastResort:lastResortPreKey];

    [[TSNetworkManager sharedManager] makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
          [storageManager storePreKeyRecords:preKeys];
          [storageManager storeSignedPreKey:signedPreKey.Id signedPreKeyRecord:signedPreKey];

          success();
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
          failureBlock(error);
        }];
}

+ (void)refreshPreKeys {
    TSAvailablePreKeysCountRequest *preKeyCountRequest = [[TSAvailablePreKeysCountRequest alloc] init];
    [[TSNetworkManager sharedManager] makeRequest:preKeyCountRequest
        success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
          NSString *preKeyCountKey = @"count";
          NSNumber *count          = [responseObject objectForKey:preKeyCountKey];

          if (count.integerValue > EPHEMERAL_PREKEYS_MINIMUM) {
              DDLogVerbose(@"Available prekeys sufficient: %@", count.stringValue);
              return;
          } else {
              [self registerPreKeysWithSuccess:^{
                DDLogInfo(@"New PreKeys registered with server.");

                [self clearSignedPreKeyRecords];
              }
                  failure:^(NSError *error) {
                    DDLogWarn(@"Failed to update prekeys with the server");
                  }];
          }
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
          DDLogError(@"Failed to retrieve the number of available prekeys.");
        }];
}

+ (void)clearSignedPreKeyRecords {
    TSRequest *currentSignedPreKey = [[TSCurrentSignedPreKeyRequest alloc] init];
    [[TSNetworkManager sharedManager] makeRequest:currentSignedPreKey
        success:^(NSURLSessionDataTask *task, NSDictionary *responseObject) {
          NSString *keyIdDictKey = @"keyId";
          NSNumber *keyId        = [responseObject objectForKey:keyIdDictKey];

          [self clearSignedPreKeyRecordsWithKeyId:keyId];

        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
          DDLogWarn(@"Failed to retrieve current prekey.");
        }];
}

+ (void)clearSignedPreKeyRecordsWithKeyId:(NSNumber *)keyId {
    if (!keyId) {
        DDLogError(@"The server returned an incomplete ");
        return;
    }

    TSStorageManager *storageManager  = [TSStorageManager sharedManager];
    SignedPreKeyRecord *currentRecord = [storageManager loadSignedPrekey:keyId.intValue];
    NSArray *allSignedPrekeys         = [storageManager loadSignedPreKeys];
    NSArray *oldSignedPrekeys         = [self removeCurrentRecord:currentRecord fromRecords:allSignedPrekeys];

    if ([oldSignedPrekeys count] > 3) {
        for (SignedPreKeyRecord *deletionCandidate in oldSignedPrekeys) {
            DDLogInfo(@"Old signed prekey record: %@", deletionCandidate.generatedAt);

            if ([deletionCandidate.generatedAt timeIntervalSinceNow] > SignedPreKeysDeletionTime) {
                [storageManager removeSignedPreKey:deletionCandidate.Id];
            }
        }
    }
}

+ (NSArray *)removeCurrentRecord:(SignedPreKeyRecord *)currentRecord fromRecords:(NSArray *)allRecords {
    NSMutableArray *oldRecords = [NSMutableArray array];

    for (SignedPreKeyRecord *record in allRecords) {
        if (currentRecord.Id != record.Id) {
            [oldRecords addObject:record];
        }
    }

    return oldRecords;
}

@end
