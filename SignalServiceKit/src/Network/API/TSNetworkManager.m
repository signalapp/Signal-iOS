//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSNetworkManager.h"
#import "AppContext.h"
#import "NSData+OWS.h"
#import "NSError+messageSending.h"
#import "NSURLSessionDataTask+StatusCode.h"
#import "OWSSignalService.h"
#import "SSKEnvironment.h"
#import "TSAccountManager.h"
#import "TSVerifyCodeRequest.h"
#import <AFNetworking/AFNetworking.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

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
    OWSAssertDebug(SSKEnvironment.shared.networkManager);

    return SSKEnvironment.shared.networkManager;
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
            success:(TSNetworkManagerSuccess)success
            failure:(TSNetworkManagerFailure)failure
{
    return [self makeRequest:request completionQueue:dispatch_get_main_queue() success:success failure:failure];
}

- (void)makeRequest:(TSRequest *)request
    completionQueue:(dispatch_queue_t)completionQueue
            success:(TSNetworkManagerSuccess)successBlock
            failure:(TSNetworkManagerFailure)failureBlock
{
    OWSAssertDebug(request);
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self makeRequestSync:request completionQueue:completionQueue success:successBlock failure:failureBlock];
    });
}

- (void)makeRequestSync:(TSRequest *)request
        completionQueue:(dispatch_queue_t)completionQueue
                success:(TSNetworkManagerSuccess)successBlock
                failure:(TSNetworkManagerFailure)failureBlock
{
    OWSAssertDebug(request);
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    OWSLogInfo(@"Making request: %@", request);

    // TODO: Remove this logging when the call connection issues have been resolved.
    TSNetworkManagerSuccess success = ^(NSURLSessionDataTask *task, _Nullable id responseObject) {
        OWSLogInfo(@"request succeeded : %@", request);

        if (request.shouldHaveAuthorizationHeaders) {
            [TSAccountManager.sharedInstance setIsDeregistered:NO];
        }

        successBlock(task, responseObject);

        [OutageDetection.sharedManager reportConnectionSuccess];
    };
    TSNetworkManagerFailure failure = [TSNetworkManager errorPrettifyingForFailureBlock:failureBlock request:request];

    AFHTTPSessionManager *sessionManager = [OWSSignalService sharedInstance].signalServiceSessionManager;
    // [OWSSignalService signalServiceSessionManager] always returns a new instance of
    // session manager, so its safe to reconfigure it here.
    sessionManager.completionQueue = completionQueue;

    if ([request isKindOfClass:[TSVerifyCodeRequest class]]) {
        // We plant the Authorization parameter ourselves, no need to double add.
        [sessionManager.requestSerializer
            setAuthorizationHeaderFieldWithUsername:((TSVerifyCodeRequest *)request).numberToValidate
                                           password:[request.parameters objectForKey:@"AuthKey"]];
        NSMutableDictionary *parameters = [request.parameters mutableCopy];
        [parameters removeObjectForKey:@"AuthKey"];
        [sessionManager PUT:request.URL.absoluteString parameters:parameters success:success failure:failure];
    } else {
        if (request.shouldHaveAuthorizationHeaders) {
            [sessionManager.requestSerializer setAuthorizationHeaderFieldWithUsername:request.authUsername
                                                                             password:request.authPassword];
        }

        // Honor the request's preferences about default cookie handling.
        //
        // Default is YES.
        sessionManager.requestSerializer.HTTPShouldHandleCookies = request.HTTPShouldHandleCookies;

        // Honor the request's headers.
        for (NSString *headerField in request.allHTTPHeaderFields) {
            NSString *headerValue = request.allHTTPHeaderFields[headerField];
            [sessionManager.requestSerializer setValue:headerValue forHTTPHeaderField:headerField];
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
            OWSLogError(@"Trying to perform HTTP operation with unknown verb: %@", request.HTTPMethod);
        }
    }
}

#ifdef DEBUG
+ (void)logCurlForTask:(NSURLSessionDataTask *)task
{
    NSMutableArray<NSString *> *curlComponents = [NSMutableArray new];
    [curlComponents addObject:@"curl"];
    // Verbose
    [curlComponents addObject:@"-v"];
    // Insecure
    [curlComponents addObject:@"-k"];
    // Method, e.g. GET
    [curlComponents addObject:@"-X"];
    [curlComponents addObject:task.originalRequest.HTTPMethod];
    // Headers
    for (NSString *header in task.originalRequest.allHTTPHeaderFields) {
        NSString *headerValue = task.originalRequest.allHTTPHeaderFields[header];
        // We don't yet support escaping header values.
        // If these asserts trip, we'll need to add that.
        OWSAssertDebug([header rangeOfString:@"'"].location == NSNotFound);
        OWSAssertDebug([headerValue rangeOfString:@"'"].location == NSNotFound);

        [curlComponents addObject:@"-H"];
        [curlComponents addObject:[NSString stringWithFormat:@"'%@: %@'", header, headerValue]];
    }
    // Body/parameters (e.g. JSON payload)
    if (task.originalRequest.HTTPBody) {
        NSString *jsonBody =
            [[NSString alloc] initWithData:task.originalRequest.HTTPBody encoding:NSUTF8StringEncoding];
        // We don't yet support escaping JSON.
        // If these asserts trip, we'll need to add that.
        OWSAssertDebug([jsonBody rangeOfString:@"'"].location == NSNotFound);
        [curlComponents addObject:@"--data-ascii"];
        [curlComponents addObject:[NSString stringWithFormat:@"'%@'", jsonBody]];
    }
    // TODO: Add support for cookies.
    [curlComponents addObject:task.originalRequest.URL.absoluteString];
    NSString *curlCommand = [curlComponents componentsJoinedByString:@" "];
    OWSLogVerbose(@"curl for failed request: %@", curlCommand);
}
#endif

+ (failureBlock)errorPrettifyingForFailureBlock:(failureBlock)failureBlock request:(TSRequest *)request
{
    OWSAssertDebug(failureBlock);
    OWSAssertDebug(request);

    return ^(NSURLSessionDataTask *_Nullable task, NSError *_Nonnull networkError) {
      NSInteger statusCode = [task statusCode];

#ifdef DEBUG
        [TSNetworkManager logCurlForTask:task];
#endif

      [OutageDetection.sharedManager reportConnectionFailure];

      NSError *error = [self errorWithHTTPCode:statusCode
                                   description:nil
                                 failureReason:nil
                            recoverySuggestion:nil
                                 fallbackError:networkError];

      switch (statusCode) {
          case 0: {
              error.isRetryable = YES;

              OWSLogWarn(@"The network request failed because of a connectivity error: %@", request);
              failureBlock(task,
                  [self errorWithHTTPCode:statusCode
                              description:NSLocalizedString(@"ERROR_DESCRIPTION_NO_INTERNET",
                                              @"Generic error used whenever Signal can't contact the server")
                            failureReason:networkError.localizedFailureReason
                       recoverySuggestion:NSLocalizedString(@"NETWORK_ERROR_RECOVERY", nil)
                            fallbackError:networkError]);
              break;
          }
          case 400: {
              OWSLogError(
                  @"The request contains an invalid parameter : %@, %@", networkError.debugDescription, request);

              error.isRetryable = NO;

              failureBlock(task, error);
              break;
          }
          case 401: {
              OWSLogError(@"The server returned an error about the authorization header: %@, %@",
                  networkError.debugDescription,
                  request);
              error.isRetryable = NO;
              [self deregisterAfterAuthErrorIfNecessary:task statusCode:statusCode];
              failureBlock(task, error);
              break;
          }
          case 403: {
              OWSLogError(
                  @"The server returned an authentication failure: %@, %@", networkError.debugDescription, request);
              error.isRetryable = NO;
              [self deregisterAfterAuthErrorIfNecessary:task statusCode:statusCode];
              failureBlock(task, error);
              break;
          }
          case 404: {
              OWSLogError(@"The requested resource could not be found: %@, %@", networkError.debugDescription, request);
              error.isRetryable = NO;
              failureBlock(task, error);
              break;
          }
          case 411: {
              OWSLogInfo(
                  @"Multi-device pairing: %ld, %@, %@", (long)statusCode, networkError.debugDescription, request);
              failureBlock(task,
                           [self errorWithHTTPCode:statusCode
                                       description:NSLocalizedString(@"MULTIDEVICE_PAIRING_MAX_DESC", @"alert title: cannot link - reached max linked devices")
                                     failureReason:networkError.localizedFailureReason
                                recoverySuggestion:NSLocalizedString(@"MULTIDEVICE_PAIRING_MAX_RECOVERY", @"alert body: cannot link - reached max linked devices")
                                     fallbackError:networkError]);
              break;
          }
          case 413: {
              OWSLogWarn(@"Rate limit exceeded: %@", request);
              failureBlock(task,
                           [self errorWithHTTPCode:statusCode
                                       description:NSLocalizedString(@"REGISTRATION_ERROR", nil)
                                     failureReason:networkError.localizedFailureReason
                                recoverySuggestion:NSLocalizedString(@"REGISTER_RATE_LIMITING_BODY", nil)
                                     fallbackError:networkError]);
              break;
          }
          case 417: {
              // TODO: Is this response code obsolete?
              OWSLogWarn(@"The number is already registered on a relay. Please unregister there first: %@", request);
              failureBlock(task,
                           [self errorWithHTTPCode:statusCode
                                       description:NSLocalizedString(@"REGISTRATION_ERROR", nil)
                                     failureReason:networkError.localizedFailureReason
                                recoverySuggestion:NSLocalizedString(@"RELAY_REGISTERED_ERROR_RECOVERY", nil)
                                     fallbackError:networkError]);
              break;
          }
          case 422: {
              OWSLogError(@"The registration was requested over an unknown transport: %@, %@",
                  networkError.debugDescription,
                  request);
              failureBlock(task, error);
              break;
          }
          default: {
              OWSLogWarn(@"Unknown error: %ld, %@, %@", (long)statusCode, networkError.debugDescription, request);
              failureBlock(task, error);
              break;
          }
      }
    };
}

+ (void)deregisterAfterAuthErrorIfNecessary:(NSURLSessionDataTask *)task statusCode:(NSInteger)statusCode
{
    OWSLogVerbose(@"Invalid auth: %@", task.originalRequest.allHTTPHeaderFields);

    // Distinguish CDS requests.
    // We don't want a bad CDS request to trigger "Signal deauth" logic.
    if ([task.originalRequest.URL.absoluteString hasPrefix:textSecureServerURL]) {
        [TSAccountManager.sharedInstance setIsDeregistered:YES];
    } else {
        OWSLogWarn(@"Ignoring %d for URL: %@", (int)statusCode, task.originalRequest.URL.absoluteString);
    }
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
