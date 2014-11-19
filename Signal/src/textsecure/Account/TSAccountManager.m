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
#import "TSNetworkManager.h"
#import "TSAccountManager.h"
#import "TSRequestVerificationCodeRequest.h"
#import "TSStorageManager+keyingMaterial.h"
#import "TSNumberVerifier.h"
#import "TSRegisterForPushRequest.h"
#import "TSRegisterWithTokenRequest.h"

typedef void(^succesfullPushRegistrationBlock)(NSData *pushToken);


@interface TSAccountManager ()

@property (nonatomic, retain) NSString *phoneNumberAwaitingVerification;

@end

@interface TSNumberVerifier ()

+ (instancetype)verifierWithPhoneNumber:(NSString*)phoneNumber;

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
        YapDatabaseConnection *dbConn = [[TSStorageManager sharedManager] databaseConnection];
        
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

+ (void)registerWithPhoneNumber:(NSString*)phoneNumber overTransport:(VerificationTransportType)transport success:(codeVerifierBlock)successBlock failure:(failedRegistrationRequestBlock)failureBlock{
    
    [[TSNetworkManager sharedManager] queueAuthenticatedRequest:[[TSRequestVerificationCodeRequest alloc]
                                                                 initRequestForPhoneNumber:phoneNumber transport:transport]
                                                        success:^(NSURLSessionDataTask *task, id responseObject) {
        long statuscode = task.statusCode;
        
        if (statuscode == 200 || statuscode == 204) {
            successBlock([TSNumberVerifier verifierWithPhoneNumber:phoneNumber]);
        } else{
            failureBlock();
        }
        
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        failureBlock();
    }];
}

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

#endif

@end
