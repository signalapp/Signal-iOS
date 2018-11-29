//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSNetworkManager.h"
#import "AppContext.h"
#import "NSError+messageSending.h"
#import "NSURLSessionDataTask+StatusCode.h"
#import "OWSError.h"
#import "OWSSignalService.h"
#import "SSKEnvironment.h"
#import "TSAccountManager.h"
#import "TSRequest.h"
#import <AFNetworking/AFNetworking.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NSErrorDomain const TSNetworkManagerErrorDomain = @"SignalServiceKit.TSNetworkManager";

BOOL IsNSErrorNetworkFailure(NSError *_Nullable error)
{
    return ([error.domain isEqualToString:TSNetworkManagerErrorDomain]
        && error.code == TSNetworkManagerErrorFailedConnection);
}

@interface TSNetworkManager ()

// This property should only be accessed on udSerialQueue.
@property (atomic, readonly) AFHTTPSessionManager *udSessionManager;
@property (atomic, readonly) NSDictionary *udSessionManagerDefaultHeaders;

@property (atomic, readonly) dispatch_queue_t udSerialQueue;

typedef void (^failureBlock)(NSURLSessionDataTask *task, NSError *error);

@end

@implementation TSNetworkManager

@synthesize udSessionManager = _udSessionManager;
@synthesize udSerialQueue = _udSerialQueue;

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

    _udSerialQueue = dispatch_queue_create("org.whispersystems.networkManager.udQueue", DISPATCH_QUEUE_SERIAL);

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

    if (request.isUDRequest) {
        dispatch_async(self.udSerialQueue, ^{
            [self makeUDRequestSync:request success:successBlock failure:failureBlock];
        });
    } else {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self makeRequestSync:request completionQueue:completionQueue success:successBlock failure:failureBlock];
        });
    }
}

- (void)makeRequestSync:(TSRequest *)request
        completionQueue:(dispatch_queue_t)completionQueue
                success:(TSNetworkManagerSuccess)successBlock
                failure:(TSNetworkManagerFailure)failureBlock
{
    OWSAssertDebug(request);
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    OWSLogInfo(@"Making Non-UD request: %@", request);

    // TODO: Remove this logging when the call connection issues have been resolved.
    TSNetworkManagerSuccess success = ^(NSURLSessionDataTask *task, _Nullable id responseObject) {
        OWSLogInfo(@"Non-UD request succeeded : %@", request);

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

    if (request.shouldHaveAuthorizationHeaders) {
        [sessionManager.requestSerializer setAuthorizationHeaderFieldWithUsername:request.authUsername
                                                                         password:request.authPassword];
    }

    // Honor the request's headers.
    for (NSString *headerField in request.allHTTPHeaderFields) {
        NSString *headerValue = request.allHTTPHeaderFields[headerField];
        [sessionManager.requestSerializer setValue:headerValue forHTTPHeaderField:headerField];
    }

    [self performRequest:request sessionManager:sessionManager success:success failure:failure];
}

// This method should only be invoked on udSerialQueue.
- (AFHTTPSessionManager *)udSessionManager
{
    if (!_udSessionManager) {
        AFHTTPSessionManager *udSessionManager = [OWSSignalService sharedInstance].signalServiceSessionManager;
        udSessionManager.completionQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        // NOTE: We could enable HTTPShouldUsePipelining here.
        _udSessionManager = udSessionManager;
        // Make a copy of the default headers for this session manager.
        _udSessionManagerDefaultHeaders = [udSessionManager.requestSerializer.HTTPRequestHeaders copy];
    }

    return _udSessionManager;
}

- (void)makeUDRequestSync:(TSRequest *)request
                  success:(TSNetworkManagerSuccess)successBlock
                  failure:(TSNetworkManagerFailure)failureBlock
{
    OWSAssertDebug(request);
    OWSAssert(!request.shouldHaveAuthorizationHeaders);
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    OWSLogInfo(@"Making UD request: %@", request);

    TSNetworkManagerSuccess success = ^(NSURLSessionDataTask *task, _Nullable id responseObject) {
        OWSLogInfo(@"UD request succeeded : %@", request);

        successBlock(task, responseObject);

        [OutageDetection.sharedManager reportConnectionSuccess];
    };
    TSNetworkManagerFailure failure = [TSNetworkManager errorPrettifyingForFailureBlock:failureBlock request:request];

    AFHTTPSessionManager *sessionManager = self.udSessionManager;

    // Clear all headers so that we don't retain headers from previous requests.
    for (NSString *headerField in sessionManager.requestSerializer.HTTPRequestHeaders.allKeys.copy) {
        [sessionManager.requestSerializer setValue:nil forHTTPHeaderField:headerField];
    }
    // Apply the default headers for this session manager.
    for (NSString *headerField in self.udSessionManagerDefaultHeaders) {
        NSString *headerValue = self.udSessionManagerDefaultHeaders[headerField];
        [sessionManager.requestSerializer setValue:headerValue forHTTPHeaderField:headerField];
    }
    // Honor the request's headers.
    for (NSString *headerField in request.allHTTPHeaderFields) {
        NSString *headerValue = request.allHTTPHeaderFields[headerField];
        [sessionManager.requestSerializer setValue:headerValue forHTTPHeaderField:headerField];
    }

    [self performRequest:request sessionManager:sessionManager success:success failure:failure];
}

- (void)performRequest:(TSRequest *)request
        sessionManager:(AFHTTPSessionManager *)sessionManager
               success:(TSNetworkManagerSuccess)success
               failure:(TSNetworkManagerFailure)failure
{
    OWSAssertDebug(request);
    OWSAssertDebug(sessionManager);
    OWSAssertDebug(success);
    OWSAssertDebug(failure);

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
        [sessionManager PUT:request.URL.absoluteString parameters:request.parameters success:success failure:failure];
    } else if ([request.HTTPMethod isEqualToString:@"DELETE"]) {
        [sessionManager DELETE:request.URL.absoluteString
                    parameters:request.parameters
                       success:success
                       failure:failure];
    } else {
        OWSLogError(@"Trying to perform HTTP operation with unknown verb: %@", request.HTTPMethod);
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
              NSError *connectivityError =
                  [self errorWithHTTPCode:TSNetworkManagerErrorFailedConnection
                              description:NSLocalizedString(@"ERROR_DESCRIPTION_NO_INTERNET",
                                              @"Generic error used whenever Signal can't contact the server")
                            failureReason:networkError.localizedFailureReason
                       recoverySuggestion:NSLocalizedString(@"NETWORK_ERROR_RECOVERY", nil)
                            fallbackError:networkError];
              connectivityError.isRetryable = YES;

              OWSLogWarn(@"The network request failed because of a connectivity error: %@", request);
              failureBlock(task, connectivityError);
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
              [self deregisterAfterAuthErrorIfNecessary:task request:request statusCode:statusCode];
              failureBlock(task, error);
              break;
          }
          case 403: {
              OWSLogError(
                  @"The server returned an authentication failure: %@, %@", networkError.debugDescription, request);
              error.isRetryable = NO;
              [self deregisterAfterAuthErrorIfNecessary:task request:request statusCode:statusCode];
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
              NSError *customError =
                  [self errorWithHTTPCode:statusCode
                              description:NSLocalizedString(@"MULTIDEVICE_PAIRING_MAX_DESC",
                                              @"alert title: cannot link - reached max linked devices")
                            failureReason:networkError.localizedFailureReason
                       recoverySuggestion:NSLocalizedString(@"MULTIDEVICE_PAIRING_MAX_RECOVERY",
                                              @"alert body: cannot link - reached max linked devices")
                            fallbackError:networkError];
              customError.isRetryable = NO;
              failureBlock(task, customError);
              break;
          }
          case 413: {
              OWSLogWarn(@"Rate limit exceeded: %@", request);
              NSError *customError = [self errorWithHTTPCode:statusCode
                                                 description:NSLocalizedString(@"REGISTER_RATE_LIMITING_ERROR", nil)
                                               failureReason:networkError.localizedFailureReason
                                          recoverySuggestion:NSLocalizedString(@"REGISTER_RATE_LIMITING_BODY", nil)
                                               fallbackError:networkError];
              customError.isRetryable = NO;
              failureBlock(task, customError);
              break;
          }
          case 417: {
              // TODO: Is this response code obsolete?
              OWSLogWarn(@"The number is already registered on a relay. Please unregister there first: %@", request);
              NSError *customError = [self errorWithHTTPCode:statusCode
                                                 description:NSLocalizedString(@"REGISTRATION_ERROR", nil)
                                               failureReason:networkError.localizedFailureReason
                                          recoverySuggestion:NSLocalizedString(@"RELAY_REGISTERED_ERROR_RECOVERY", nil)
                                               fallbackError:networkError];
              customError.isRetryable = NO;
              failureBlock(task, customError);
              break;
          }
          case 422: {
              OWSLogError(@"The registration was requested over an unknown transport: %@, %@",
                  networkError.debugDescription,
                  request);
              error.isRetryable = NO;
              failureBlock(task, error);
              break;
          }
          default: {
              OWSLogWarn(@"Unknown error: %ld, %@, %@", (long)statusCode, networkError.debugDescription, request);
              error.isRetryable = NO;
              failureBlock(task, error);
              break;
          }
      }
    };
}

+ (void)deregisterAfterAuthErrorIfNecessary:(NSURLSessionDataTask *)task
                                    request:(TSRequest *)request
                                 statusCode:(NSInteger)statusCode {
    OWSLogVerbose(@"Invalid auth: %@", task.originalRequest.allHTTPHeaderFields);

    // We only want to de-register for:
    //
    // * Auth errors...
    // * ...received from Signal service...
    // * ...that used standard authorization.
    //
    // * We don't want want to deregister for:
    //
    // * CDS requests.
    // * Requests using UD auth.
    // * etc.
    if ([task.originalRequest.URL.absoluteString hasPrefix:textSecureServerURL]
        && request.shouldHaveAuthorizationHeaders) {
        [TSAccountManager.sharedInstance setIsDeregistered:YES];
    } else {
        OWSLogWarn(@"Ignoring %d for URL: %@", (int)statusCode, task.originalRequest.URL.absoluteString);
    }
}

+ (NSError *)errorWithHTTPCode:(NSInteger)code
                   description:(NSString *)description
                 failureReason:(NSString *)failureReason
            recoverySuggestion:(NSString *)recoverySuggestion
                 fallbackError:(NSError *)fallbackError
{
    OWSAssertDebug(fallbackError);

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

    dict[NSUnderlyingErrorKey] = fallbackError;

    return [NSError errorWithDomain:TSNetworkManagerErrorDomain code:code userInfo:dict];
}

@end
