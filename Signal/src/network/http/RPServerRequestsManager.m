//
//  CallServerRequests.m
//  Signal
//
//  Created by Frederic Jacobs on 31/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//
#import "HttpRequest.h"
#import "RPServerRequestsManager.h"
#import "Constraints.h"
#import "CryptoTools.h"
#import "DataUtil.h"
#import "Environment.h"
#import "HostNameEndPoint.h"
#import "SignalKeyingStorage.h"
#import "Util.h"

#import "AFHTTPSessionManager+SignalMethods.h"

@interface RPServerRequestsManager ()

@property (nonatomic, retain)AFHTTPSessionManager *operationManager;

@end


@implementation RPServerRequestsManager

MacrosSingletonImplemention

- (id)init{
    self = [super init];
    
    if (self) {
        HostNameEndPoint *endpoint = Environment.getCurrent.masterServerSecureEndPoint.hostNameEndPoint;
        NSURL *endPointURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@:%hu", endpoint.hostname, endpoint.port]];
        NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.defaultSessionConfiguration;
        self.operationManager = [[AFHTTPSessionManager alloc] initWithBaseURL:endPointURL sessionConfiguration:sessionConf];
        self.operationManager.securityPolicy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeNone];
        self.operationManager.securityPolicy.allowInvalidCertificates = YES;
        NSString *certPath = [NSBundle.mainBundle pathForResource:@"redphone" ofType:@"cer"];
        NSData *certData = [NSData dataWithContentsOfFile:certPath];
        SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)(certData));
        self.operationManager.securityPolicy.pinnedCertificates = @[(__bridge_transfer NSData *)SecCertificateCopyData(cert)];
    }
    return self;
}

- (void)performRequest:(RPAPICall*)apiCall success:(void (^)(NSURLSessionDataTask *task, id responseObject))success failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure{
    
    self.operationManager.requestSerializer  = apiCall.requestSerializer;
    self.operationManager.responseSerializer = apiCall.responseSerializer;
    
    switch (apiCall.method) {
        case HTTP_GET:
            [self.operationManager GET:apiCall.endPoint parameters:apiCall.parameters success:success failure:failure];
            break;
            
        case HTTP_PUT:
            [self.operationManager PUT:apiCall.endPoint parameters:apiCall.parameters success:success failure:failure];
            break;
            
        case HTTP_POST:
            [self.operationManager POST:apiCall.endPoint parameters:apiCall.parameters success:success failure:failure];
            break;
            
        case HTTP_DELETE:
            NSLog(@"endpoint %@, request serializer %@",apiCall.endPoint,apiCall.requestSerializer);
            [self.operationManager DELETE:apiCall.endPoint parameters:apiCall.parameters success:success failure:failure];
            break;
            
        case SIGNAL_BUSY:
            [self.operationManager BUSY:apiCall.endPoint parameters:apiCall.parameters success:success failure:failure];
            break;
            
        case SIGNAL_RING:
            [self.operationManager RING:apiCall.endPoint parameters:apiCall.parameters success:success failure:failure];
            break;
    }
}

- (TOCFuture*)futureForRequest:(RPAPICall*)apiCall{
    TOCFutureSource *requestFutureSource = [TOCFutureSource new];
    
    [self performRequest:apiCall success:^(NSURLSessionDataTask *task, id responseObject) {
        [requestFutureSource trySetResult:task.response];
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        [requestFutureSource trySetFailure:error];
    }];
    
    return [requestFutureSource future];
}

@end
