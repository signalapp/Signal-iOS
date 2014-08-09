//
//  CallServerRequests.m
//  Signal
//
//  Created by Frederic Jacobs on 31/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//
#import "HttpRequest.h"
#import "CallServerRequestsManager.h"
#import "DataUtil.h"
#import "Environment.h"
#import "HostNameEndPoint.h"
#import "SGNKeychainUtil.h"

#define defaultRequestTimeout

@interface CallServerRequestsManager ()

@property (nonatomic, retain)AFHTTPSessionManager *operationManager;

@end


@implementation CallServerRequestsManager

MacrosSingletonImplemention

- (id)init{
    self = [super init];
    
    if (self) {
        HostNameEndPoint *endpoint = [[[Environment getCurrent]masterServerSecureEndPoint] hostNameEndPoint];
        NSURL *endPointURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@:%hu", endpoint.hostname, endpoint.port]];
        NSURLSessionConfiguration *sessionConf = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        self.operationManager = [[AFHTTPSessionManager alloc] initWithBaseURL:endPointURL sessionConfiguration:sessionConf];
        [self.operationManager setSecurityPolicy:[AFSecurityPolicy policyWithPinningMode:AFSSLPinningModePublicKey]];
        
        NSString *certPath = [[NSBundle mainBundle] pathForResource:@"whisperReal" ofType:@"cer"];
        NSData *certData = [NSData dataWithContentsOfFile:certPath];
        
        SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)(certData));
        
        self.operationManager.securityPolicy.pinnedCertificates = @[(__bridge_transfer NSData *)SecCertificateCopyData(cert)];
        self.operationManager.securityPolicy.allowInvalidCertificates = YES; // We use a custom certificate, not signed by a CA.
        self.operationManager.responseSerializer                      = [AFJSONResponseSerializer serializer];
    }
    return self;
}

- (void)registerPushToken:(NSData*)deviceToken success:(void (^)(NSURLSessionDataTask *task, id responseObject))success
failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure{
    self.operationManager.requestSerializer = [self basicAuthenticationSerializer];
    
    [self.operationManager PUT:[NSString stringWithFormat:@"/apn/%@",[deviceToken encodedAsHexString]] parameters:@{} success:success failure:failure];
}

- (AFHTTPRequestSerializer*)basicAuthenticationSerializer{
    AFHTTPRequestSerializer *serializer = [AFHTTPRequestSerializer serializer];
    [serializer setValue:[HttpRequest computeBasicAuthorizationTokenForLocalNumber:[SGNKeychainUtil localNumber]andPassword:[SGNKeychainUtil serverAuthPassword]] forHTTPHeaderField:@"Authorization"];
    return serializer;
}

@end
