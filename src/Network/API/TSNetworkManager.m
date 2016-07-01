//
//  TSNetworkManager.m
//  TextSecureiOS
//
//  Created by Frederic Jacobs on 9/27/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import <AFNetworking/AFNetworking.h>

#import "OWSHTTPSecurityPolicy.h"

#import "NSURLSessionDataTask+StatusCode.h"
#import "TSAccountManager.h"
#import "TSNetworkManager.h"
#import "TSStorageManager+keyingMaterial.h"
#import "TSVerifyCodeRequest.h"

#define TSNetworkManagerDomain @"org.whispersystems.signal.networkManager"

@interface TSNetworkManager ()

@property AFHTTPSessionManager *operationManager;

typedef void (^failureBlock)(NSURLSessionDataTask *task, NSError *error);

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
        self.operationManager =
            [[AFHTTPSessionManager alloc] initWithBaseURL:[[NSURL alloc] initWithString:textSecureServerURL]
                                     sessionConfiguration:sessionConf];
        self.operationManager.securityPolicy = [OWSHTTPSecurityPolicy sharedPolicy];
    }
    return self;
}

#pragma mark Manager Methods

- (void)makeRequest:(TSRequest *)request
            success:(void (^)(NSURLSessionDataTask *task, id responseObject))success
            failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failureBlock {
    void (^failure)(NSURLSessionDataTask *task, NSError *error) =
        [TSNetworkManager errorPrettifyingForFailureBlock:failureBlock];

    self.operationManager.requestSerializer  = [AFJSONRequestSerializer serializer];
    self.operationManager.responseSerializer = [AFJSONResponseSerializer serializer];

    if ([request isKindOfClass:[TSVerifyCodeRequest class]]) {
        // We plant the Authorization parameter ourselves, no need to double add.
        [self.operationManager.requestSerializer
            setAuthorizationHeaderFieldWithUsername:((TSVerifyCodeRequest *)request).numberToValidate
                                           password:[request.parameters objectForKey:@"AuthKey"]];
        [request.parameters removeObjectForKey:@"AuthKey"];
        [self.operationManager PUT:[textSecureServerURL stringByAppendingString:request.URL.absoluteString]
                        parameters:request.parameters
                           success:success
                           failure:failure];
    } else {
        if (![request isKindOfClass:[TSRequestVerificationCodeRequest class]]) {
            [self.operationManager.requestSerializer
                setAuthorizationHeaderFieldWithUsername:[TSAccountManager localNumber]
                                               password:[TSStorageManager serverAuthToken]];
        }

        if ([request.HTTPMethod isEqualToString:@"GET"]) {
            [self.operationManager GET:[textSecureServerURL stringByAppendingString:request.URL.absoluteString]
                            parameters:request.parameters
                              progress:nil
                               success:success
                               failure:failure];
        } else if ([request.HTTPMethod isEqualToString:@"POST"]) {
            [self.operationManager POST:[textSecureServerURL stringByAppendingString:request.URL.absoluteString]
                             parameters:request.parameters
                               progress:nil
                                success:success
                                failure:failure];
        } else if ([request.HTTPMethod isEqualToString:@"PUT"]) {
            [self.operationManager PUT:[textSecureServerURL stringByAppendingString:request.URL.absoluteString]
                            parameters:request.parameters
                               success:success
                               failure:failure];
        } else if ([request.HTTPMethod isEqualToString:@"DELETE"]) {
            [self.operationManager DELETE:[textSecureServerURL stringByAppendingString:request.URL.absoluteString]
                               parameters:request.parameters
                                  success:success
                                  failure:failure];
        } else {
            DDLogError(@"Trying to perform HTTP operation with unknown verb: %@", request.HTTPMethod);
        }
    }
}

+ (failureBlock)errorPrettifyingForFailureBlock:(failureBlock)failureBlock {
    return ^(NSURLSessionDataTask *_Nullable task, NSError *_Nonnull networkError) {
      NSInteger statusCode = [task statusCode];
      NSError *error       = [self errorWithHTTPCode:statusCode
                                   description:nil
                                 failureReason:nil
                            recoverySuggestion:nil
                                 fallbackError:networkError];

      switch (statusCode) {
          case 0: {
              DDLogWarn(@"The network request failed because of a connectivity error.");
              failureBlock(task,
                           [self errorWithHTTPCode:statusCode
                                       description:NSLocalizedString(@"NETWORK_ERROR_DESC", nil)
                                     failureReason:networkError.localizedFailureReason
                                recoverySuggestion:NSLocalizedString(@"NETWORK_ERROR_RECOVERY", nil)
                                     fallbackError:networkError]);
              break;
          }
          case 400: {
              DDLogError(@"The request contains an invalid parameter : %@", networkError.debugDescription);
              failureBlock(task, error);
              break;
          }
          case 401: {
              DDLogError(@"The server returned an error about the authorization header: %@",
                         networkError.debugDescription);
              failureBlock(task, error);
              break;
          }
          case 403: {
              DDLogError(@"The server returned an authentication failure: %@", networkError.debugDescription);
              failureBlock(task, error);
              break;
          }
          case 404: {
              DDLogError(@"The requested resource could not be found: %@", networkError.debugDescription);
              failureBlock(task, error);
              break;
          }
          case 411: {
              failureBlock(task,
                           [self errorWithHTTPCode:statusCode
                                       description:NSLocalizedString(@"MULTIDEVICE_PAIRING_MAX_DESC", nil)
                                     failureReason:networkError.localizedFailureReason
                                recoverySuggestion:NSLocalizedString(@"MULTIDEVICE_PAIRING_MAX_RECOVERY", nil)
                                     fallbackError:networkError]);
              break;
          }
          case 413: {
              DDLogWarn(@"Rate limit exceeded");
              failureBlock(task,
                           [self errorWithHTTPCode:statusCode
                                       description:NSLocalizedString(@"REGISTRATION_ERROR", nil)
                                     failureReason:networkError.localizedFailureReason
                                recoverySuggestion:NSLocalizedString(@"REGISTER_RATE_LIMITING_BODY", nil)
                                     fallbackError:networkError]);
              break;
          }
          case 417: {
              DDLogWarn(@"The number is already registered on a relay. Please unregister there first.");
              failureBlock(task,
                           [self errorWithHTTPCode:statusCode
                                       description:NSLocalizedString(@"REGISTRATION_ERROR", nil)
                                     failureReason:networkError.localizedFailureReason
                                recoverySuggestion:NSLocalizedString(@"RELAY_REGISTERED_ERROR_RECOVERY", nil)
                                     fallbackError:networkError]);
              break;
          }
          case 422: {
              DDLogError(@"The registration was requested over an unknown transport: %@",
                         networkError.debugDescription);
              failureBlock(task, error);
              break;
          }

          default: {
              failureBlock(task, error);
              break;
          }
      }
    };
}

+ (NSError *)errorWithHTTPCode:(NSInteger)code
                   description:(NSString *)description
                 failureReason:(NSString *)failureReason
            recoverySuggestion:(NSString *)recoverySuggestion
                 fallbackError:(NSError *_Nonnull)fallbackError {
    if (!description) {
        description = fallbackError.localizedDescription;
    }
    if (!failureReason) {
        failureReason = fallbackError.localizedFailureReason;
    }
    if (!recoverySuggestion) {
        recoverySuggestion = fallbackError.localizedRecoverySuggestion;
    }

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    if (description) {
        [dict setObject:description forKey:NSLocalizedDescriptionKey];
    }
    if (failureReason) {
        [dict setObject:failureReason forKey:NSLocalizedFailureReasonErrorKey];
    }
    if (recoverySuggestion) {
        [dict setObject:recoverySuggestion forKey:NSLocalizedRecoverySuggestionErrorKey];
    }

    NSData *failureData = fallbackError.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];

    if (failureData) {
        [dict setObject:failureData forKey:AFNetworkingOperationFailingURLResponseDataErrorKey];
    }

    return [NSError errorWithDomain:TSNetworkManagerDomain code:code userInfo:dict];
}

@end
