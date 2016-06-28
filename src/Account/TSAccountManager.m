//
//  TSAccountManagement.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "NSData+Base64.h"
#import "NSData+hexString.h"
#import "NSURLSessionDataTask+StatusCode.h"

#import "SecurityUtils.h"
#import "TSAccountManager.h"
#import "TSNetworkManager.h"
#import "TSPreKeyManager.h"
#import "TSRedPhoneTokenRequest.h"
#import "TSSocketManager.h"
#import "TSStorageManager+keyingMaterial.h"

@interface TSAccountManager ()

@property (nonatomic, retain) NSString *phoneNumberAwaitingVerification;

@end

@implementation TSAccountManager

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id sharedInstance = nil;
    dispatch_once(&onceToken, ^{
      sharedInstance = [self.class new];
    });

    return sharedInstance;
}

+ (BOOL)isRegistered {
    return [TSStorageManager localNumber] ? YES : NO;
}

+ (void)didRegister {
    TSAccountManager *sharedManager = [self sharedInstance];
    __strong NSString *phoneNumber  = sharedManager.phoneNumberAwaitingVerification;

    if (!phoneNumber) {
        @throw [NSException exceptionWithName:@"RegistrationFail" reason:@"Internal Corrupted State" userInfo:nil];
    }

    [TSStorageManager storePhoneNumber:phoneNumber];
}

+ (NSString *)localNumber {
    TSAccountManager *sharedManager = [self sharedInstance];
    NSString *awaitingVerif         = sharedManager.phoneNumberAwaitingVerification;
    if (awaitingVerif) {
        return awaitingVerif;
    }

    return [TSStorageManager localNumber];
}

+ (uint32_t)getOrGenerateRegistrationId {
    YapDatabaseConnection *dbConn   = [[TSStorageManager sharedManager] newDatabaseConnection];
    __block uint32_t registrationID = 0;

    [dbConn readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      registrationID = [[transaction objectForKey:TSStorageLocalRegistrationId
                                     inCollection:TSStorageUserAccountCollection] unsignedIntValue];
    }];

    if (registrationID == 0) {
        registrationID = (uint32_t)arc4random_uniform(16380) + 1;

        [dbConn readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
          [transaction setObject:[NSNumber numberWithUnsignedInteger:registrationID]
                          forKey:TSStorageLocalRegistrationId
                    inCollection:TSStorageUserAccountCollection];
        }];
    }

    return registrationID;
}

+ (void)registerForPushNotifications:(NSString *)pushToken
                           voipToken:(NSString *)voipToken
                             success:(successCompletionBlock)success
                             failure:(failedBlock)failureBlock {
    [[TSNetworkManager sharedManager]
        makeRequest:[[TSRegisterForPushRequest alloc] initWithPushIdentifier:pushToken voipIdentifier:voipToken]
        success:^(NSURLSessionDataTask *task, id responseObject) {
          success();
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
          failureBlock(error);
        }];
}

+ (void)registerWithPhoneNumber:(NSString *)phoneNumber
                        success:(successCompletionBlock)successBlock
                        failure:(failedBlock)failureBlock
                smsVerification:(BOOL)isSMS

{
    if ([self isRegistered]) {
        failureBlock([NSError errorWithDomain:@"tsaccountmanager.verify" code:4000 userInfo:nil]);
        return;
    }

    [[TSNetworkManager sharedManager]
        makeRequest:[[TSRequestVerificationCodeRequest alloc]
                        initWithPhoneNumber:phoneNumber
                                  transport:isSMS ? TSVerificationTransportSMS : TSVerificationTransportVoice]
        success:^(NSURLSessionDataTask *task, id responseObject) {
          successBlock();
          TSAccountManager *manager               = [self sharedInstance];
          manager.phoneNumberAwaitingVerification = phoneNumber;
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
          failureBlock(error);
        }];
}

+ (void)rerequestSMSWithSuccess:(successCompletionBlock)successBlock failure:(failedBlock)failureBlock {
    TSAccountManager *manager = [self sharedInstance];
    NSString *number          = manager.phoneNumberAwaitingVerification;

    assert(number);

    [self registerWithPhoneNumber:number success:successBlock failure:failureBlock smsVerification:YES];
}

+ (void)rerequestVoiceWithSuccess:(successCompletionBlock)successBlock failure:(failedBlock)failureBlock {
    TSAccountManager *manager = [self sharedInstance];
    NSString *number          = manager.phoneNumberAwaitingVerification;

    assert(number);

    [self registerWithPhoneNumber:number success:successBlock failure:failureBlock smsVerification:NO];
}

+ (void)verifyAccountWithCode:(NSString *)verificationCode
                    pushToken:(NSString *)pushToken
                    voipToken:(NSString *)voipToken
                      success:(successCompletionBlock)successBlock
                      failure:(failedBlock)failureBlock {
    NSString *authToken    = [self generateNewAccountAuthenticationToken];
    NSString *signalingKey = [self generateNewSignalingKeyToken];
    NSString *phoneNumber  = ((TSAccountManager *)[self sharedInstance]).phoneNumberAwaitingVerification;

    assert(signalingKey);
    assert(authToken);
    assert(pushToken);
    assert(phoneNumber);

    TSVerifyCodeRequest *request = [[TSVerifyCodeRequest alloc] initWithVerificationCode:verificationCode
                                                                               forNumber:phoneNumber
                                                                            signalingKey:signalingKey
                                                                                 authKey:authToken];

    [[TSNetworkManager sharedManager] makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
          NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
          long statuscode             = response.statusCode;

          if (statuscode == 200 || statuscode == 204) {
              [TSStorageManager storeServerToken:authToken signalingKey:signalingKey];

              [self registerForPushNotifications:pushToken
                  voipToken:voipToken
                  success:^{
                    [self registerPreKeys:^{
                      [TSSocketManager becomeActiveFromForeground];
                      successBlock();
                    }
                                  failure:failureBlock];
                  }
                  failure:^(NSError *error) {
                    failureBlock(error);
                  }];
          }
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
          DDLogError(@"Error registering with TextSecure: %@", error.debugDescription);
          failureBlock(error);
        }];
}

+ (void)registerPreKeysAfterPush:(NSString *)pushToken
                       voipToken:(NSString *)voipToken
                         success:(successCompletionBlock)successBlock
                         failure:(failedBlock)failureBlock {
    [self registerForPushNotifications:pushToken
                             voipToken:voipToken
                               success:^{
                                 [self registerPreKeys:successBlock failure:failureBlock];
                               }
                               failure:failureBlock];
}

+ (void)registerPreKeys:(successCompletionBlock)successBlock failure:(failedBlock)failureBlock {
    [TSPreKeyManager registerPreKeysWithSuccess:^{
      successBlock();
    }
                                        failure:failureBlock];
}

#pragma mark Server keying material

+ (NSString *)generateNewAccountAuthenticationToken {
    NSData *authToken        = [SecurityUtils generateRandomBytes:16];
    NSString *authTokenPrint = [[NSData dataWithData:authToken] hexadecimalString];
    return authTokenPrint;
}

+ (NSString *)generateNewSignalingKeyToken {
    /*The signalingKey is 32 bytes of AES material (256bit AES) and 20 bytes of
     * Hmac key material (HmacSHA1) concatenated into a 52 byte slug that is
     * base64 encoded. */
    NSData *signalingKeyToken        = [SecurityUtils generateRandomBytes:52];
    NSString *signalingKeyTokenPrint = [[NSData dataWithData:signalingKeyToken] base64EncodedString];
    return signalingKeyTokenPrint;
}

+ (void)obtainRPRegistrationToken:(void (^)(NSString *rpRegistrationToken))success failure:(failedBlock)failureBlock {
    [[TSNetworkManager sharedManager] makeRequest:[[TSRedPhoneTokenRequest alloc] init]
        success:^(NSURLSessionDataTask *task, id responseObject) {
          success([responseObject objectForKey:@"token"]);
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
          failureBlock(error);
        }];
}

+ (void)unregisterTextSecureWithSuccess:(successCompletionBlock)success failure:(failedBlock)failureBlock {
    [[TSNetworkManager sharedManager] makeRequest:[[TSUnregisterAccountRequest alloc] init]
        success:^(NSURLSessionDataTask *task, id responseObject) {
          success();
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
          failureBlock(error);
        }];
}

@end
