//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSNetworkManager.h"
#import "NSURLSessionDataTask+StatusCode.h"
#import "OWSSignalService.h"
#import "TSAccountManager.h"
#import "TSVerifyCodeRequest.h"
#import <AFNetworking/AFNetworking.h>

NSString *const TSNetworkManagerDomain = @"org.whispersystems.signal.networkManager";

BOOL IsNSErrorNetworkFailure(NSError *_Nullable error)
{
    return ([error.domain isEqualToString:TSNetworkManagerDomain] && error.code == 0);
}

@interface TSNetworkManager ()

typedef void (^failureBlock)(NSURLSessionDataTask *task, NSError *error);

@end

@implementation TSNetworkManager

#pragma mark Singleton implementation

+ (instancetype)sharedManager
{
    static TSNetworkManager *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] initDefault];
    });
    return sharedMyManager;
}


- (instancetype)initDefault
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    return self;
}

#pragma mark Manager Methods

- (void)makeRequest:(TSRequest *)request
            success:(void (^)(NSURLSessionDataTask *task, id responseObject))success
            failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failureBlock
{
    DDLogInfo(@"%@ Making request: %@", self.tag, request);

    void (^failure)(NSURLSessionDataTask *task, NSError *error) =
        [TSNetworkManager errorPrettifyingForFailureBlock:failureBlock];

    AFHTTPSessionManager *sessionManager = [OWSSignalService sharedInstance].signalServiceSessionManager;

    if ([request isKindOfClass:[TSVerifyCodeRequest class]]) {
        // We plant the Authorization parameter ourselves, no need to double add.
        [sessionManager.requestSerializer
            setAuthorizationHeaderFieldWithUsername:((TSVerifyCodeRequest *)request).numberToValidate
                                           password:[request.parameters objectForKey:@"AuthKey"]];
        [request.parameters removeObjectForKey:@"AuthKey"];
        [sessionManager PUT:request.URL.absoluteString parameters:request.parameters success:success failure:failure];
    } else {
        if (![request isKindOfClass:[TSRequestVerificationCodeRequest class]]) {
            [sessionManager.requestSerializer
                setAuthorizationHeaderFieldWithUsername:[TSAccountManager localNumber]
                                               password:[TSAccountManager serverAuthToken]];
        }

        if ([request.HTTPMethod isEqualToString:@"GET"]) {
            [sessionManager GET:request.URL.absoluteString
                     parameters:request.parameters
                       progress:nil
                        success:success
                        failure:failure];
        } else if ([request.HTTPMethod isEqualToString:@"POST"]) {
            [sessionManager POST:request.URL.absoluteString
                      parameters:request.parameters
                        progress:nil
                         success:success
                         failure:failure];
        } else if ([request.HTTPMethod isEqualToString:@"PUT"]) {
            [sessionManager PUT:request.URL.absoluteString
                     parameters:request.parameters
                        success:success
                        failure:failure];
        } else if ([request.HTTPMethod isEqualToString:@"DELETE"]) {
            [sessionManager DELETE:request.URL.absoluteString
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
                              description:NSLocalizedString(@"ERROR_DESCRIPTION_NO_INTERNET",
                                              @"Generic error used whenver Signal can't contact the server")
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

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
