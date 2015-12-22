//
//  AFHTTPSessionManager+SignalMethods.m
//  Signal
//
//  Created by Frederic Jacobs on 05/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "AFHTTPSessionManager+SignalMethods.h"

@interface AFHTTPSessionManager ()

- (NSURLSessionDataTask *)dataTaskWithHTTPMethod:(NSString *)method
                                       URLString:(NSString *)URLString
                                      parameters:(id)parameters
                                         success:(void (^)(NSURLSessionDataTask *, id))success
                                         failure:(void (^)(NSURLSessionDataTask *, NSError *))failure;

@end

@implementation AFHTTPSessionManager (SignalMethods)

- (NSURLSessionDataTask *)BUSY:(NSString *)URLString
                    parameters:(id)parameters
                       success:(void (^)(NSURLSessionDataTask *task, id responseObject))success
                       failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure {
    NSURLSessionDataTask *dataTask =
        [self dataTaskWithHTTPMethod:@"BUSY" URLString:URLString parameters:parameters success:success failure:failure];
    [dataTask resume];

    return dataTask;
}

- (NSURLSessionDataTask *)RING:(NSString *)URLString
                    parameters:(id)parameters
                       success:(void (^)(NSURLSessionDataTask *task, id responseObject))success
                       failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure {
    NSURLSessionDataTask *dataTask =
        [self dataTaskWithHTTPMethod:@"RING" URLString:URLString parameters:parameters success:success failure:failure];
    [dataTask resume];

    return dataTask;
}


@end
