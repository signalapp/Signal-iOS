//
//  TSNetworkManager.h
//  TextSecureiOS
//
//  Created by Frederic Jacobs on 9/27/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AFNetworking/AFHTTPRequestOperationManager.h>
#import "TSRequest.h"
#import "TSRequestVerificationCodeRequest.h"

@interface TSNetworkManager : NSObject

+ (id)sharedManager;
/* requests outside of the TS Server */
- (void) queueUnauthenticatedRequest:(TSRequest*) request success:(void (^)(AFHTTPRequestOperation *operation, id responseObject))successCompletionBlock failure: (void (^)(AFHTTPRequestOperation *operation, NSError *error)) failureCompletionBlock;

/* requests inside the TS Server */
- (void) queueAuthenticatedRequest:(TSRequest*) request success:(void (^)(NSURLSessionDataTask *task, id responseObject))success failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure;

@end
