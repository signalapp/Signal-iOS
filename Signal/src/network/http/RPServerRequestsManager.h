//
//  CallServerRequests.h
//  Signal
//
//  Created by Frederic Jacobs on 31/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RPAPICall.h"

#import <CollapsingFutures.h>

@interface RPServerRequestsManager : NSObject

MacrosSingletonInterface

- (void)performRequest:(RPAPICall*)apiCall success:(void (^)(NSURLSessionDataTask *task, id responseObject))success failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure;

- (TOCFuture*)futureForRequest:(RPAPICall*)apiCall;

@end
