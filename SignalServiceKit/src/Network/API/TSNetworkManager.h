//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

/**
 *  TSNetworkManager imports all TSRequests to prevent massive imports
 in classes that call TSNetworkManager
 */
#import "TSAllocAttachmentRequest.h"
#import "TSAttachmentRequest.h"
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
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const TSNetworkManagerDomain;

BOOL IsNSErrorNetworkFailure(NSError *_Nullable error);

@interface TSNetworkManager : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

- (void)makeRequest:(TSRequest *)request
            success:(void (^)(NSURLSessionDataTask *task, id responseObject))success
            failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure NS_SWIFT_NAME(makeRequest(_:success:failure:));

@end

NS_ASSUME_NONNULL_END
