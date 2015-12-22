//
//  CallServerRequests.m
//  Signal
//
//  Created by Frederic Jacobs on 31/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//
#import "Environment.h"
#import "RPServerRequestsManager.h"

#import "AFHTTPSessionManager+SignalMethods.h"
#import "AFSecurityOWSPolicy.h"

@interface RPServerRequestsManager ()

@property (nonatomic, strong) AFHTTPSessionManager *operationManager;

@end


@implementation RPServerRequestsManager

+ (instancetype)sharedManager {
    static RPServerRequestsManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      sharedManager = [self new];
    });
    return sharedManager;
}

- (id)init {
    self = [super init];

    if (self) {
        NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
        HostNameEndPoint *endpoint               = Environment.getCurrent.masterServerSecureEndPoint.hostNameEndPoint;
        NSURL *endPointURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@:%d", endpoint.hostname, 443]];
        self.operationManager =
            [[AFHTTPSessionManager alloc] initWithBaseURL:endPointURL sessionConfiguration:sessionConfig];
        self.operationManager.securityPolicy = [AFSecurityOWSPolicy OWS_PinningPolicy];
    }
    return self;
}

- (void)performRequest:(RPAPICall *)apiCall
               success:(void (^)(NSURLSessionDataTask *task, id responseObject))success
               failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure {
    self.operationManager.requestSerializer  = apiCall.requestSerializer;
    self.operationManager.responseSerializer = apiCall.responseSerializer;

    switch (apiCall.method) {
        case HTTP_GET:
            [self.operationManager GET:apiCall.endPoint
                            parameters:apiCall.parameters
                              progress:nil
                               success:success
                               failure:failure];
            break;

        case HTTP_PUT:
            [self.operationManager PUT:apiCall.endPoint parameters:apiCall.parameters success:success failure:failure];
            break;

        case HTTP_POST:
            [self.operationManager POST:apiCall.endPoint
                             parameters:apiCall.parameters
                               progress:nil
                                success:success
                                failure:failure];
            break;

        case HTTP_DELETE:
            [self.operationManager DELETE:apiCall.endPoint
                               parameters:apiCall.parameters
                                  success:success
                                  failure:failure];
            break;

        case SIGNAL_BUSY:
            [self.operationManager BUSY:apiCall.endPoint parameters:apiCall.parameters success:success failure:failure];
            break;

        case SIGNAL_RING:
            [self.operationManager RING:apiCall.endPoint parameters:apiCall.parameters success:success failure:failure];
            break;
    }
}

- (TOCFuture *)futureForRequest:(RPAPICall *)apiCall {
    TOCFutureSource *requestFutureSource = [TOCFutureSource new];

    [self performRequest:apiCall
        success:^(NSURLSessionDataTask *task, id responseObject) {
          [requestFutureSource trySetResult:task.response];
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
          [requestFutureSource trySetFailure:error];
        }];

    return [requestFutureSource future];
}

@end
