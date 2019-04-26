//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSNetworkManager.h"
#import "AppContext.h"
#import "NSError+messageSending.h"
#import "NSURLSessionDataTask+StatusCode.h"
#import "OWSError.h"
#import "OWSQueues.h"
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

dispatch_queue_t NetworkManagerQueue()
{
    static dispatch_queue_t serialQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        serialQueue = dispatch_queue_create("org.whispersystems.networkManager", DISPATCH_QUEUE_SERIAL);
    });
    return serialQueue;
}

#pragma mark -

@interface OWSSessionManager : NSObject

@property (nonatomic, readonly) AFHTTPSessionManager *sessionManager;
@property (nonatomic, readonly) NSDictionary *defaultHeaders;

@end

#pragma mark -

@implementation OWSSessionManager

#pragma mark - Dependencies

- (OWSSignalService *)signalService
{
    return [OWSSignalService sharedInstance];
}

#pragma mark -

- (instancetype)init
{
    AssertOnDispatchQueue(NetworkManagerQueue());

    self = [super init];
    if (!self) {
        return self;
    }

    _sessionManager = [self.signalService buildSignalServiceSessionManager];
    self.sessionManager.completionQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    // NOTE: We could enable HTTPShouldUsePipelining here.
    // Make a copy of the default headers for this session manager.
    _defaultHeaders = [self.sessionManager.requestSerializer.HTTPRequestHeaders copy];

    return self;
}

//  TSNetworkManager.serialQueue
- (void)performRequest:(TSRequest *)request
            canUseAuth:(BOOL)canUseAuth
               success:(TSNetworkManagerSuccess)success
               failure:(TSNetworkManagerFailure)failure
{
    AssertOnDispatchQueue(NetworkManagerQueue());
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

    if (canUseAuth && request.shouldHaveAuthorizationHeaders) {
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

// You might be asking: "why use a pool at all? We're only using the session manager
// on the serial queue, so can't we just have two session managers (1 UD, 1 non-UD)
// that we use for all requests?"
//
// That assumes that the session managers are not stateful in a way where concurrent
// requests can interfere with each other. I audited the AFNetworking codebase and my
// reading is that sessions managers are safe to use in that way - that the state of
// their properties (e.g. header values) is only used when building the request and
// can be safely changed after performRequest is complete.
//
// But I decided that I didn't want to (silently) bake that assumption into the
// codebase, since the stakes are high. The session managers aren't expensive. IMO
// better to use a pool and not re-use a session manager until its request succeeds
// or fails.
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
    AssertOnDispatchQueue(NetworkManagerQueue());

    OWSSessionManager *_Nullable sessionManager = [self.pool lastObject];
    if (sessionManager) {
        [self.pool removeLastObject];
    } else {
        sessionManager = [OWSSessionManager new];
    }
    OWSAssertDebug(sessionManager);
    return sessionManager;
}

- (void)returnToPool:(OWSSessionManager *)sessionManager
{
    AssertOnDispatchQueue(NetworkManagerQueue());

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

@end

#pragma mark -

@implementation TSNetworkManager

#pragma mark - Dependencies

+ (TSAccountManager *)tsAccountManager
{
    return TSAccountManager.sharedInstance;
}

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
            success:(TSNetworkManagerSuccess)success
            failure:(TSNetworkManagerFailure)failure
{
    OWSAssertDebug(request);
    OWSAssertDebug(success);
    OWSAssertDebug(failure);

    dispatch_async(NetworkManagerQueue(), ^{
        [self makeRequestSync:request completionQueue:completionQueue success:success failure:failure];
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

    BOOL isUDRequest = request.isUDRequest;
    NSString *label = (isUDRequest ? @"UD request" : @"Non-UD request");
    BOOL canUseAuth = !isUDRequest;
    if (isUDRequest) {
        OWSAssert(!request.shouldHaveAuthorizationHeaders);
    }
    OWSLogInfo(@"Making %@: %@", label, request);

    OWSSessionManagerPool *sessionManagerPool
        = (isUDRequest ? self.udSessionManagerPool : self.nonUdSessionManagerPool);
    OWSSessionManager *sessionManager = [sessionManagerPool get];

    TSNetworkManagerSuccess success = ^(NSURLSessionDataTask *task, _Nullable id responseObject) {
        dispatch_async(NetworkManagerQueue(), ^{
            [sessionManagerPool returnToPool:sessionManager];
        });

        dispatch_async(completionQueue, ^{
            OWSLogInfo(@"%@ succeeded : %@", label, request);

            if (canUseAuth && request.shouldHaveAuthorizationHeaders) {
                [TSNetworkManager.tsAccountManager setIsDeregistered:NO];
            }

            successParam(task, responseObject);

            [OutageDetection.sharedManager reportConnectionSuccess];
        });
    };
    TSNetworkManagerSuccess failure = ^(NSURLSessionDataTask *task, NSError *error) {
        dispatch_async(NetworkManagerQueue(), ^{
            [sessionManagerPool returnToPool:sessionManager];
        });

        [TSNetworkManager
            handleNetworkFailure:^(NSURLSessionDataTask *task, NSError *error) {
                dispatch_async(completionQueue, ^{
                    failureParam(task, error);
                });
            }
                         request:request
                            task:task
                           error:error];
    };

    [sessionManager performRequest:request canUseAuth:canUseAuth success:success failure:failure];
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

+ (void)handleNetworkFailure:(TSNetworkManagerFailure)failureBlock
                     request:(TSRequest *)request
                        task:(NSURLSessionDataTask *)task
                       error:(NSError *)networkError
{
    OWSAssertDebug(failureBlock);
    OWSAssertDebug(request);
    OWSAssertDebug(task);
    OWSAssertDebug(networkError);

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
            OWSLogError(@"The request contains an invalid parameter : %@, %@", networkError.debugDescription, request);

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
            OWSLogInfo(@"Multi-device pairing: %ld, %@, %@", (long)statusCode, networkError.debugDescription, request);
            NSError *customError = [self errorWithHTTPCode:statusCode
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
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.tsAccountManager.isRegisteredAndReady) {
                [self.tsAccountManager setIsDeregistered:YES];
            } else {
                OWSLogWarn(
                    @"Ignoring auth failure; not registered and ready: %@.", task.originalRequest.URL.absoluteString);
            }
        });
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
