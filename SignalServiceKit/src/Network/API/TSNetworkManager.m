//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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

NS_ASSUME_NONNULL_BEGIN

NSErrorDomain const TSNetworkManagerErrorDomain = @"SignalServiceKit.TSNetworkManager";

BOOL IsNSErrorNetworkFailure(NSError *_Nullable error)
{
    return ([error.domain isEqualToString:TSNetworkManagerErrorDomain]
        && error.code == TSNetworkManagerErrorFailedConnection);
}

#pragma mark -

@interface OWSSessionManager : NSObject

@property (nonatomic) AFHTTPSessionManager *sessionManager;
@property (nonatomic, readonly) NSDictionary *defaultHeaders;

@end

#pragma mark -

@implementation OWSSessionManager

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.sessionManager = [OWSSignalService sharedInstance].signalServiceSessionManager;
    self.sessionManager.completionQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    // NOTE: We could enable HTTPShouldUsePipelining here.
    // Make a copy of the default headers for this session manager.
    _defaultHeaders = [self.sessionManager.requestSerializer.HTTPRequestHeaders copy];

    return self;
}

- (void)performRequest:(TSRequest *)request
               success:(TSNetworkManagerSuccess)success
               failure:(TSNetworkManagerFailure)failure
{
    OWSAssertDebug(request);
    OWSAssertDebug(success);
    OWSAssertDebug(failure);

    // Clear all headers so that we don't retain headers from previous requests.
    for (NSString *headerField in self.sessionManager.requestSerializer.HTTPRequestHeaders.allKeys.copy) {
        [self.sessionManager.requestSerializer setValue:nil forHTTPHeaderField:headerField];
    }

    // Apply the default headers for this session manager.
    for (NSString *headerField in self.defaultHeaders) {
        NSString *headerValue = self.defaultHeaders[headerField];
        [self.sessionManager.requestSerializer setValue:headerValue forHTTPHeaderField:headerField];
    }

    if (request.shouldHaveAuthorizationHeaders) {
        [self.sessionManager.requestSerializer setAuthorizationHeaderFieldWithUsername:request.authUsername
                                                                              password:request.authPassword];
    }

    // Honor the request's headers.
    for (NSString *headerField in request.allHTTPHeaderFields) {
        NSString *headerValue = request.allHTTPHeaderFields[headerField];
        [self.sessionManager.requestSerializer setValue:headerValue forHTTPHeaderField:headerField];
    }

    if ([request.HTTPMethod isEqualToString:@"GET"]) {
        [self.sessionManager GET:request.URL.absoluteString
                      parameters:request.parameters
                        progress:nil
                         success:success
                         failure:failure];
    } else if ([request.HTTPMethod isEqualToString:@"POST"]) {
        [self.sessionManager POST:request.URL.absoluteString
                       parameters:request.parameters
                         progress:nil
                          success:success
                          failure:failure];
    } else if ([request.HTTPMethod isEqualToString:@"PUT"]) {
        [self.sessionManager PUT:request.URL.absoluteString
                      parameters:request.parameters
                         success:success
                         failure:failure];
    } else if ([request.HTTPMethod isEqualToString:@"DELETE"]) {
        [self.sessionManager DELETE:request.URL.absoluteString
                         parameters:request.parameters
                            success:success
                            failure:failure];
    } else {
        OWSLogError(@"Trying to perform HTTP operation with unknown verb: %@", request.HTTPMethod);
    }
}

@end

#pragma mark -

@interface OWSSessionManagerPool : NSObject

@property (nonatomic) NSMutableArray<OWSSessionManager *> *pool;

@end

#pragma mark -

@implementation OWSSessionManagerPool

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.pool = [NSMutableArray new];

    return self;
}

- (OWSSessionManager *)get
{
    OWSSessionManager *_Nullable sessionManager = [self.pool lastObject];
    if (sessionManager) {
        OWSLogVerbose(@"Cache hit.");
        [self.pool removeLastObject];
    } else {
        OWSLogVerbose(@"Cache miss.");
        sessionManager = [OWSSessionManager new];
    }
    OWSAssertDebug(sessionManager);
    return sessionManager;
}

- (void)returnToPool:(OWSSessionManager *)sessionManager
{
    OWSAssertDebug(sessionManager);
    const NSUInteger kMaxPoolSize = 3;
    if (self.pool.count >= kMaxPoolSize) {
        // Discard
        return;
    }
    [self.pool addObject:sessionManager];
}

@end

#pragma mark -

@interface TSNetworkManager ()

// These properties should only be accessed on serialQueue.
@property (atomic, readonly) OWSSessionManagerPool *udSessionManagerPool;
@property (atomic, readonly) OWSSessionManagerPool *nonUdSessionManagerPool;

@property (atomic, readonly) dispatch_queue_t serialQueue;

typedef void (^failureBlock)(NSURLSessionDataTask *task, NSError *error);

@end

#pragma mark -

@implementation TSNetworkManager

#pragma mark - Dependencies

+ (TSAccountManager *)tsAccountManager
{
    return TSAccountManager.sharedInstance;
}

#pragma mark -

@synthesize serialQueue = _serialQueue;

#pragma mark - Singleton

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

    _udSessionManagerPool = [OWSSessionManagerPool new];
    _nonUdSessionManagerPool = [OWSSessionManagerPool new];
    _serialQueue = dispatch_queue_create("org.whispersystems.networkManager", DISPATCH_QUEUE_SERIAL);

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

    dispatch_async(self.serialQueue, ^{
        if (request.isUDRequest) {
            [self makeUDRequestSync:request success:successBlock failure:failureBlock];
        } else {
            [self makeRequestSync:request completionQueue:completionQueue success:successBlock failure:failureBlock];
        }
    });
}

- (void)makeRequestSync:(TSRequest *)request
        completionQueue:(dispatch_queue_t)completionQueue
                success:(TSNetworkManagerSuccess)successParam
                failure:(TSNetworkManagerFailure)failureParam
{
    OWSAssertDebug(request);
    OWSAssertDebug(successParam);
    OWSAssertDebug(failureParam);

    OWSLogInfo(@"Making Non-UD request: %@", request);


    OWSSessionManagerPool *sessionManagerPool = self.nonUdSessionManagerPool;
    OWSSessionManager *sessionManager = [sessionManagerPool get];

    TSNetworkManagerSuccess success = ^(NSURLSessionDataTask *task, _Nullable id responseObject) {
        dispatch_async(self.serialQueue, ^{
            [sessionManagerPool returnToPool:sessionManager];
        });

        dispatch_async(completionQueue, ^{
            OWSLogInfo(@"Non-UD request succeeded : %@", request);

            if (request.shouldHaveAuthorizationHeaders) {
                [TSNetworkManager.tsAccountManager setIsDeregistered:NO];
            }

            successParam(task, responseObject);

            [OutageDetection.sharedManager reportConnectionSuccess];
        });
    };
    TSNetworkManagerSuccess failure = ^(NSURLSessionDataTask *task, NSError *error) {
        dispatch_async(self.serialQueue, ^{
            [sessionManagerPool returnToPool:sessionManager];
        });

        // TODO: Refactor this.
        [TSNetworkManager
            errorPrettifyingForFailureBlock:^(NSURLSessionDataTask *task, NSError *error) {
                dispatch_async(completionQueue, ^{
                    failureParam(task, error);
                });
            }
                                    request:request](task, error);
    };

    [sessionManager performRequest:request success:success failure:failure];
}

- (void)makeUDRequestSync:(TSRequest *)request
                  success:(TSNetworkManagerSuccess)successParam
                  failure:(TSNetworkManagerFailure)failureParam
{
    OWSAssertDebug(request);
    OWSAssert(!request.shouldHaveAuthorizationHeaders);
    OWSAssertDebug(successParam);
    OWSAssertDebug(failureParam);

    OWSLogInfo(@"Making UD request: %@", request);

    OWSSessionManagerPool *sessionManagerPool = self.udSessionManagerPool;
    OWSSessionManager *sessionManager = [sessionManagerPool get];

    TSNetworkManagerSuccess success = ^(NSURLSessionDataTask *task, _Nullable id responseObject) {
        OWSLogInfo(@"UD request succeeded : %@", request);

        dispatch_async(self.serialQueue, ^{
            [sessionManagerPool returnToPool:sessionManager];
        });

        successParam(task, responseObject);

        [OutageDetection.sharedManager reportConnectionSuccess];
    };
    TSNetworkManagerSuccess failure = ^(NSURLSessionDataTask *task, NSError *error) {
        dispatch_async(self.serialQueue, ^{
            [sessionManagerPool returnToPool:sessionManager];
        });

        // TODO: Refactor this.
        [TSNetworkManager errorPrettifyingForFailureBlock:failureParam request:request](task, error);
    };

    [sessionManager performRequest:request success:success failure:failure];
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
        if (self.tsAccountManager.isRegisteredAndReady) {
            [self.tsAccountManager setIsDeregistered:YES];
        } else {
            OWSFailDebug(
                @"Ignoring auth failure; not registered and ready: %@.", task.originalRequest.URL.absoluteString);
        }
    } else {
        OWSLogWarn(@"Ignoring %d for URL: %@", (int)statusCode, task.originalRequest.URL.absoluteString);
    }
}

+ (NSError *)errorWithHTTPCode:(NSInteger)code
                   description:(nullable NSString *)description
                 failureReason:(nullable NSString *)failureReason
            recoverySuggestion:(nullable NSString *)recoverySuggestion
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

NS_ASSUME_NONNULL_END
