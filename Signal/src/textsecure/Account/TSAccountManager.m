//
//  TSAccountManagement.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "Constraints.h"
#import "NSData+Base64.h"
#import "NSData+hexString.h"
#import "NSURLSessionDataTask+StatusCode.h"

#import "SecurityUtils.h"
#import "TSNetworkManager.h"
#import "TSAccountManager.h"
#import "TSStorageManager+keyingMaterial.h"
#import "TSPreKeyManager.h"
#import "TSRegisterForPushRequest.h"
#import "TSRegisterWithTokenRequest.h"

@interface TSAccountManager ()

@property (nonatomic, retain) NSString *phoneNumberAwaitingVerification;

@end

@implementation TSAccountManager

+ (BOOL)isRegistered {
    return [[TSStorageManager sharedManager] boolForKey:TSStorageIsRegistered inCollection:TSStorageInternalSettingsCollection];
}

+ (void)setRegistered:(BOOL)registered{
    [[TSStorageManager sharedManager] setObject:registered?@YES:@NO forKey:TSStorageIsRegistered inCollection:TSStorageInternalSettingsCollection];
}

+ (NSString *)registeredNumber {
    YapDatabaseConnection *dbConn = [[TSStorageManager sharedManager] databaseConnection];
    __block NSString *phoneNumber;
    
    [dbConn readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        phoneNumber  = [transaction objectForKey:TSStorageRegisteredNumberKey inCollection:TSStorageUserAccountCollection];
    }];
    
    return phoneNumber;
}

+ (int)getOrGenerateRegistrationId {
    YapDatabaseConnection *dbConn = [[TSStorageManager sharedManager] databaseConnection];
    __block int registrationID;
    
    [dbConn readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        registrationID  = [[transaction objectForKey:TSStorageLocalRegistrationId inCollection:TSStorageUserAccountCollection] intValue];
    }];
    
    if (!registrationID) {
        int localIdentifier = random()%16380;
        
        [dbConn readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [transaction setObject:[NSNumber numberWithInt:localIdentifier]
                            forKey:TSStorageLocalRegistrationId
                      inCollection:TSStorageUserAccountCollection];
        }];
    }
    
    return registrationID;
}

#if TARGET_OS_IPHONE

+ (void)registerForPushNotifications:(NSData *)pushToken success:(successCompletionBlock)success failure:(failedVerificationBlock)failureBlock{
 
    NSString *stringToken = [[pushToken description] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<> "]];
    
    [[TSNetworkManager sharedManager] queueAuthenticatedRequest:[[TSRegisterForPushRequest alloc] initWithPushIdentifier:stringToken] success:^(NSURLSessionDataTask *task, id responseObject) {
        success();
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        switch ([task statusCode]) {
            case 401:
                failureBlock(kTSRegistrationFailureAuthentication);
                break;
            case 415:
                failureBlock(kTSRegistrationFailureRequest);
                break;
            default:
                failureBlock(kTSRegistrationFailureNetwork);
                break;
        }
    }];
}

+ (void)registerWithRedPhoneToken:(NSString*)tsToken pushToken:(NSData*)pushToken success:(successCompletionBlock)successBlock failure:(failedVerificationBlock)failureBlock{
    NSLog(@"PushToken:%@ TStoken: %@", pushToken, tsToken);
    
    NSString *authToken           = [self generateNewAccountAuthenticationToken];
    NSString *signalingKey        = [self generateNewSignalingKeyToken];
    NSString *phoneNumber         = [[tsToken componentsSeparatedByString:@":"] objectAtIndex:0];
    NSLog(@"Phone Number %@", phoneNumber);
    
    require(phoneNumber != nil);
    require(signalingKey != nil);
    require(authToken != nil);
    require(pushToken != nil);
    
    TSRegisterWithTokenRequest *request = [[TSRegisterWithTokenRequest alloc] initWithVerificationToken:tsToken signalingKey:signalingKey authKey:authToken number:phoneNumber];
    
    [[TSNetworkManager sharedManager] queueAuthenticatedRequest:request success:^(NSURLSessionDataTask *task, id responseObject) {
        
        NSHTTPURLResponse *response   = (NSHTTPURLResponse *)task.response;
        long statuscode               = response.statusCode;
        
        if (statuscode == 200 || statuscode == 204) {
            
            [TSStorageManager storeServerToken:authToken signalingKey:signalingKey phoneNumber:phoneNumber];
            
            [self registerForPushNotifications:pushToken success:^{
                successBlock();
            } failure:^(TSRegistrationFailure failureType) {
                failureBlock(kTSRegistrationFailureNetwork);
            }];
        } else{
            failureBlock(kTSRegistrationFailureNetwork);
        }
        
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        failureBlock(kTSRegistrationFailureNetwork);
    }];
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


#endif

@end
