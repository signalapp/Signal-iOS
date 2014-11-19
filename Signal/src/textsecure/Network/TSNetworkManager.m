//
//  TSNetworkManager.m
//  TextSecureiOS
//
//  Created by Frederic Jacobs on 9/27/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import <AFNetworking/AFNetworking.h>

#import "TSAccountManager.h"
#import "TSConstants.h"
#import "TSNetworkManager.h"
#import "TSRequest.h"
#import "TSServerCodeVerificationRequest.h"
#import "TSStorageManager+keyingMaterial.h"
#import "TSUploadAttachment.h"

@interface TSNetworkManager ()

@property AFHTTPSessionManager *operationManager;

@end

@implementation TSNetworkManager

#pragma mark Singleton implementation

+ (id)sharedManager {
    static TSNetworkManager *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] init];
    });
    return sharedMyManager;
}

- (id)init {
    if (self = [super init]) {
        NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        self.operationManager = [[AFHTTPSessionManager alloc] initWithBaseURL:[[NSURL alloc] initWithString:textSecureServerURL] sessionConfiguration:sessionConf];
        //self.operationManager.responseSerializer                      = [AFJSONResponseSerializer serializer];
        self.operationManager.securityPolicy.allowInvalidCertificates = YES;
        //        NSString *certPath = [NSBundle.mainBundle pathForResource:@"whisperReal" ofType:@"cer"];
        //        NSData *certData = [NSData dataWithContentsOfFile:certPath];
        //        SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)(certData));
        //        self.operationManager.securityPolicy.pinnedCertificates = @[(__bridge_transfer NSData *)SecCertificateCopyData(cert)];
        //        self.operationManager.securityPolicy.SSLPinningMode     = AFSSLPinningModeCertificate;
    }
    return self;
}

#pragma mark Manager Methods

- (void) queueUnauthenticatedRequest:(TSRequest*) request success:(void (^)(AFHTTPRequestOperation *operation, id responseObject))successCompletionBlock failure: (void (^)(AFHTTPRequestOperation *operation, NSError *error)) failureCompletionBlock{
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    
    [operation  setCompletionBlockWithSuccess:successCompletionBlock failure:failureCompletionBlock];
    [self.operationManager.operationQueue addOperation:operation];
}

- (void) queueAuthenticatedRequest:(TSRequest*) request success:(void (^)(NSURLSessionDataTask *task, id responseObject))success failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure {
    if ([request isKindOfClass:[TSRequestVerificationCodeRequest class]]) {
        // The only unauthenticated request is the initial request for a verification code
        self.operationManager.requestSerializer = [AFJSONRequestSerializer serializer];
        [self.operationManager GET:[textSecureServerURL stringByAppendingString:request.URL.absoluteString] parameters:request.parameters success:success failure:failure];
        
    } else if ([request isKindOfClass:[TSServerCodeVerificationRequest class]]){
        // We plant the Authorization parameter ourselves, no need to double add.
        self.operationManager.requestSerializer = [AFJSONRequestSerializer serializer];
        [self.operationManager.requestSerializer setAuthorizationHeaderFieldWithUsername:((TSServerCodeVerificationRequest*)request).numberToValidate password:[request.parameters objectForKey:@"AuthKey"]];
        
        [request.parameters removeObjectForKey:@"AuthKey"];
        
        [self.operationManager PUT:[textSecureServerURL stringByAppendingString:request.URL.absoluteString] parameters:request.parameters success:success failure:failure];
    }
    else{
        // For all other equests, we do add an authorization header
        self.operationManager.requestSerializer  = [AFJSONRequestSerializer serializer];
        self.operationManager.responseSerializer = [AFJSONResponseSerializer serializer];
        
        [self.operationManager.requestSerializer setAuthorizationHeaderFieldWithUsername:[TSAccountManager registeredNumber] password:[TSStorageManager serverAuthToken]];
        
        if ([request.HTTPMethod isEqualToString:@"GET"]) {
            [self.operationManager GET:[textSecureServerURL stringByAppendingString:request.URL.absoluteString] parameters:request.parameters success:success failure:failure];
        } else if ([request.HTTPMethod isEqualToString:@"POST"]){
            [self.operationManager POST:[textSecureServerURL stringByAppendingString:request.URL.absoluteString] parameters:request.parameters success:success failure:failure];
        } else if ([request.HTTPMethod isEqualToString:@"PUT"]){
            [self.operationManager PUT:[textSecureServerURL stringByAppendingString:request.URL.absoluteString] parameters:request.parameters success:success failure:failure];
        }
        else if ([request.HTTPMethod isEqualToString:@"DELETE"]){
            [self.operationManager DELETE:[textSecureServerURL stringByAppendingString:request.URL.absoluteString] parameters:request.parameters success:success failure:failure];
        }
    }
}


@end
