//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

/**
 *  TSNetworkManager imports all TSRequests to prevent massive imports
 in classes that call TSNetworkManager
 */
#import "TSAvailablePreKeysCountRequest.h"
#import "TSContactsIntersectionRequest.h"
#import "TSCurrentSignedPreKeyRequest.h"
#import "TSRecipientPrekeyRequest.h"
#import "TSRegisterForPushRequest.h"
#import "TSRegisterPrekeysRequest.h"
#import "TSRequestVerificationCodeRequest.h"
#import "TSSubmitMessageRequest.h"
#import "TSUnregisterAccountRequest.h"
#import "TSUpdateAttributesRequest.h"
#import "TSVerifyCodeRequest.h"
#import <AFNetworking/AFHTTPSessionManager.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const TSNetworkManagerDomain;

BOOL IsNSErrorNetworkFailure(NSError *_Nullable error);

typedef void (^TSNetworkManagerSuccess)(NSURLSessionDataTask *task, id responseObject);
typedef void (^TSNetworkManagerFailure)(NSURLSessionDataTask *task, NSError *error);

@interface TSNetworkManager : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

- (void)makeRequest:(TSRequest *)request
            success:(TSNetworkManagerSuccess)success
            failure:(TSNetworkManagerFailure)failure NS_SWIFT_NAME(makeRequest(_:success:failure:));

- (void)makeRequest:(TSRequest *)request
    completionQueue:(dispatch_queue_t)completionQueue
            success:(TSNetworkManagerSuccess)success
            failure:(TSNetworkManagerFailure)failure NS_SWIFT_NAME(makeRequest(_:shouldCompleteOnMainQueue
:success
:failure
:));

@end

NS_ASSUME_NONNULL_END
