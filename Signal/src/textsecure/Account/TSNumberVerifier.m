//
//  TSNumberVerifier.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 31/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "NSData+Base64.h"
#import "NSData+hexString.h"

#import "SecurityUtils.h"
#import "TSAccountManager.h"
#import "TSRegisterWithTokenRequest.h"
#import "TSServerCodeVerificationRequest.h"
#import "TSStorageManager+keyingMaterial.h"
#import "TSNetworkManager.h"
#import "TSNumberVerifier.h"

#import "TSPrekeyManager.h"

@interface TSNumberVerifier ()

@property (nonatomic, readonly) NSString *phoneNumber;

@end

@implementation TSNumberVerifier

- (instancetype)initWithNumber:(NSString*)string {
    self = [super init];
    
    if (self) {
        _phoneNumber = string;
    }

    return self;
}

+ (instancetype)verifierWithPhoneNumber:(NSString*)phoneNumber {
    TSNumberVerifier *verifier = [[TSNumberVerifier alloc] initWithNumber:phoneNumber];
    return verifier;
}

+ (void)registerPhoneNumber:(NSString*)phoneNumber withRedPhoneToken:(NSString*)registrationToken success:(successCompletionBlock)successBlock failure:(failedVerificationBlock)failureBlock{
    NSString *authToken           = [self generateNewAccountAuthenticationToken];
    NSString *signalingKey        = [self generateNewSignalingKeyToken];
    
    TSRegisterWithTokenRequest *request = [[TSRegisterWithTokenRequest alloc] initWithVerificationToken:registrationToken signalingKey:signalingKey authKey:authToken];
    
    [[TSNetworkManager sharedManager] queueAuthenticatedRequest:request success:^(NSURLSessionDataTask *task, id responseObject) {
        
        NSHTTPURLResponse *response   = (NSHTTPURLResponse *)task.response;
        long statuscode               = response.statusCode;
        
        if (statuscode == 200 || statuscode == 204) {
            
            [TSStorageManager storeServerToken:authToken signalingKey:signalingKey phoneNumber:phoneNumber];
            
            [[self class] registerPushIdWithSuccess:successBlock failure:failureBlock];
            
        } else{
            failureBlock(kTSRegistrationFailureNetwork);
        }
        
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        
    }];
    
    
}

- (void)verifyCode:(NSString*)verificationCode success:(successCompletionBlock)successBlock failure:(failedVerificationBlock)failureBlock {
    NSString *authToken           = [[self class] generateNewAccountAuthenticationToken];
    NSString *signalingKey        = [[self class] generateNewSignalingKeyToken];
    NSString *phoneNumber         = self.phoneNumber;
    
    TSServerCodeVerificationRequest *request = [[TSServerCodeVerificationRequest alloc] initWithVerificationCode:verificationCode signalingKey:signalingKey authKey:authToken];
    request.numberToValidate = phoneNumber;
    
    [[TSNetworkManager sharedManager] queueAuthenticatedRequest:request success:^(NSURLSessionDataTask *task, id responseObject) {
        
        NSHTTPURLResponse *response   = (NSHTTPURLResponse *)task.response;
        long statuscode               = response.statusCode;
        
        if (statuscode == 200 || statuscode == 204) {
            
            [TSStorageManager storeServerToken:authToken signalingKey:signalingKey phoneNumber:phoneNumber];
    
            [[self class] registerPushIdWithSuccess:successBlock failure:failureBlock];
            
        } else{
            failureBlock(kTSRegistrationFailureNetwork);
        }
        
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        NSHTTPURLResponse *response   = (NSHTTPURLResponse *)task.response;
        long statuscode               = response.statusCode;
        
        switch (statuscode) {
            case 403: // Wrong verification code
                failureBlock(kTSRegistrationFailureWrongCode);
                break;
            case 413: // Rate limit exceeded
                failureBlock(kTSRegistrationFailureRateLimit);
                break;
            case 417: // Number already registered
                [[self class] registerPushIdWithSuccess:successBlock failure:failureBlock];
                break;
            default:
                failureBlock(kTSRegistrationFailureNetwork);
                break;
        }
    }];
}



+ (void)registerPushIdWithSuccess:(successCompletionBlock)successBlock failure:(failedVerificationBlock)failureBlock {
    [TSAccountManager registerForPushNotifications:[@"A FAKE TOKEN" dataUsingEncoding:NSUTF8StringEncoding] success:^{
        [self registerPreKeys:successBlock failure:failureBlock];
    } failure:failureBlock];;
    
}

+ (void)registerPreKeys:(successCompletionBlock)successBlock failure:(failedVerificationBlock)failureBlock {
    [TSPreKeyManager registerPreKeysWithSuccess:^{
        [TSAccountManager setRegistered:YES];
        successBlock();
    } failure:failureBlock];
}


#pragma mark Server keying material

+ (NSString*)generateNewAccountAuthenticationToken {
    NSData    *authToken              = [SecurityUtils generateRandomBytes:16];
    NSString  *authTokenPrint         = [[NSData dataWithData:authToken] hexadecimalString];
    return authTokenPrint;
}

+ (NSString*)generateNewSignalingKeyToken {
    /*The signalingKey is 32 bytes of AES material (256bit AES) and 20 bytes of Hmac key material (HmacSHA1) concatenated into a 52 byte slug that is base64 encoded. */
    NSData    *signalingKeyToken      = [SecurityUtils generateRandomBytes:52];
    NSString  *signalingKeyTokenPrint = [[NSData dataWithData:signalingKeyToken] base64EncodedString];
    return signalingKeyTokenPrint;
}

@end
