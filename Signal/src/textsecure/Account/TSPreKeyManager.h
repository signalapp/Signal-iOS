//
//  TSPrekeyManager.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 07/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSConstants.h"
#import "TSAccountManager.h"

// Time before deletion of signed PreKeys (measured in seconds)
#define SignedPreKeysDeletionTime 14*24*60*60

@interface TSPreKeyManager : NSObject

+ (void)registerPreKeysWithSuccess:(successCompletionBlock)success failure:(failedVerificationBlock)failureBlock;

+ (void)refreshPreKeys;

@end
