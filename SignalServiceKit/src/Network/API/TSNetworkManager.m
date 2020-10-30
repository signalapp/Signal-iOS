//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "TSNetworkManager.h"
#import "AppContext.h"
#import "MIMETypeUtil.h"
#import "NSError+OWSOperation.h"
#import "NSURLSessionDataTask+OWS_HTTP.h"
#import "OWSError.h"
#import "OWSQueues.h"
#import "OWSSignalService.h"
#import "SSKEnvironment.h"
#import "TSAccountManager.h"
#import "TSRequest.h"
#import <AFNetworking/AFHTTPSessionManager.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSErrorDomain const TSNetworkManagerErrorDomain = @"SignalServiceKit.TSNetworkManager";
NSString *const TSNetworkManagerErrorRetryAfterKey = @"TSNetworkManagerError.RetryAfter";

BOOL IsNetworkConnectivityFailure(NSError *_Nullable error)
{
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        switch (error.code) {
            case kCFURLErrorTimedOut:
            case kCFURLErrorCannotConnectToHost:
            case kCFURLErrorNetworkConnectionLost:
            case kCFURLErrorDNSLookupFailed:
            case kCFURLErrorNotConnectedToInternet:
            case kCFURLErrorSecureConnectionFailed:
                // TODO: We might want to add kCFURLErrorCannotFindHost.
                return YES;
            default:
                break;
        }
    }
    BOOL isObjCNetworkConnectivityFailure = ([error.domain isEqualToString:TSNetworkManagerErrorDomain]
        && error.code == TSNetworkManagerErrorFailedConnection);
    BOOL isNetworkProtocolError = ([error.domain isEqualToString:NSPOSIXErrorDomain] && error.code == 100);

    if (isObjCNetworkConnectivityFailure) {
        return YES;
    } else if (isNetworkProtocolError) {
        return YES;
    } else if ([TSNetworkManager isSwiftNetworkConnectivityError:error]) {
        return YES;
    } else {
        return NO;
    }
}

NSNumber *_Nullable HTTPStatusCodeForError(NSError *_Nullable error)
{
    NSNumber *_Nullable afHttpStatusCode = error.afHttpStatusCode;
    if (afHttpStatusCode.integerValue > 0) {
        return afHttpStatusCode;
    }
    NSNumber *_Nullable swiftStatusCode = [TSNetworkManager swiftHTTPStatusCodeForError:error];
    if (swiftStatusCode.integerValue > 0) {
        return swiftStatusCode;
    }
    return nil;
}

NSDate *_Nullable HTTPRetryAfterDateForError(NSError *_Nullable error)
{
    NSDate *retryAfterDate = nil;

    // Different errors may represent a retry after in different ways
    retryAfterDate = retryAfterDate ?: error.afRetryAfterDate;
    retryAfterDate = retryAfterDate ?: [TSNetworkManager swiftHTTPRetryAfterDateForError:error];
    retryAfterDate = retryAfterDate ?: error.userInfo[TSNetworkManagerErrorRetryAfterKey];
    return retryAfterDate;
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
@property (nonatomic, readonly) NSDate *createdDate;

@end

#pragma mark -

@implementation OWSSessionManager

#pragma mark - Dependencies

- (OWSSignalService *)signalService
{
    return [OWSSignalService shared];
}

#pragma mark -

- (instancetype)init
{
    AssertOnDispatchQueue(NetworkManagerQueue());

    self = [super init];
    if (!self) {
        return self;
    }

    // TODO: Use OWSUrlSession instead.
    _sessionManager = [self.signalService sessionManagerForMainSignalService];
    self.sessionManager.completionQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    // NOTE: We could enable HTTPShouldUsePipelining here.
    // Make a copy of the default headers for this session manager.
    _defaultHeaders = [self.sessionManager.requestSerializer.HTTPRequestHeaders copy];
    _createdDate = [NSDate new];

    return self;
}

- (void)performRequest:(TSRequest *)request
            canUseAuth:(BOOL)canUseAuth
               success:(TSNetworkManagerSuccess)success
               failure:(TSNetworkManagerFailure)failure
{
    AssertOnDispatchQueue(NetworkManagerQueue());
    OWSAssertDebug(request);
    OWSAssertDebug(success);
    OWSAssertDebug(failure);

    if (AppExpiry.shared.isExpired) {
        NSURLSessionDataTask *task = [[NSURLSessionDataTask alloc] init];
        NSError *error = OWSErrorMakeAssertionError(@"App is expired.");
        failure(task, error);
        return;
    }

    // Clear all headers so that we don't retain headers from previous requests.
    for (NSString *headerField in self.sessionManager.requestSerializer.HTTPRequestHeaders.allKeys.copy) {
        [self.sessionManager.requestSerializer setValue:nil forHTTPHeaderField:headerField];
    }

    OWSHttpHeaders *httpHeaders = [OWSHttpHeaders new];
    [httpHeaders addHeaders:request.allHTTPHeaderFields overwriteOnConflict:NO];

    // Apply the default headers for this session manager.
    [httpHeaders addHeaders:self.defaultHeaders overwriteOnConflict:NO];

    // Set User-Agent header.
    [httpHeaders addHeader:OWSURLSession.kUserAgentHeader
                      value:OWSURLSession.signalIosUserAgent
        overwriteOnConflict:YES];

    if (canUseAuth && request.shouldHaveAuthorizationHeaders) {
        OWSAssertDebug(request.authUsername.length > 0);
        OWSAssertDebug(request.authPassword.length > 0);
        [self.sessionManager.requestSerializer setAuthorizationHeaderFieldWithUsername:request.authUsername
                                                                              password:request.authPassword];
    }

    // Most of TSNetwork requests are destined for the Signal Service.
    // When we are domain fronting, we have to target a different host and add a path prefix.
    // For common Signal-Service requests the host/path-prefix logic is handled by the
    // sessionManager.
    //
    // However, for CDS requests, we need to:
    //  With CC enabled, use the service fronting Hostname but a custom path-prefix
    //  With CC disabled, use the custom directory host, and no path-prefix
    NSString *requestURLString;
    if (self.signalService.isCensorshipCircumventionActive && request.customCensorshipCircumventionPrefix.length > 0) {
        // All fronted requests go through the same host
        NSURL *customBaseURL = [self.signalService.domainFrontBaseURL
            URLByAppendingPathComponent:request.customCensorshipCircumventionPrefix];
        NSURL *_Nullable requestURL = [OWSURLSession buildUrlWithString:request.URL.absoluteString
                                                                baseUrl:customBaseURL];
        OWSAssertDebug(requestURL != nil);
        requestURLString = requestURL.absoluteString;
    } else if (request.customHost) {
        NSURL *customBaseURL = [NSURL URLWithString:request.customHost];
        OWSAssertDebug(customBaseURL);
        requestURLString = [NSURL URLWithString:request.URL.absoluteString relativeToURL:customBaseURL].absoluteString;
    } else {
        // requests for the signal-service (with or without censorship circumvention)
        requestURLString = request.URL.absoluteString;
    }
    OWSAssertDebug(requestURLString.length > 0);

    // Honor the request's headers.
    for (NSString *headerField in httpHeaders.headers) {
        NSString *_Nullable headerValue = httpHeaders.headers[headerField];
        OWSAssertDebug(headerValue != nil);
        [self.sessionManager.requestSerializer setValue:headerValue forHTTPHeaderField:headerField];
    }

    if ([request.HTTPMethod isEqualToString:@"GET"]) {
        [self.sessionManager GET:requestURLString
                      parameters:request.parameters
                        progress:nil
                         success:success
                         failure:failure];
    } else if ([request.HTTPMethod isEqualToString:@"POST"]) {
        [self.sessionManager POST:requestURLString
                       parameters:request.parameters
                         progress:nil
                          success:success
                          failure:failure];
    } else if ([request.HTTPMethod isEqualToString:@"PUT"]) {
        [self.sessionManager PUT:requestURLString parameters:request.parameters success:success failure:failure];
    } else if ([request.HTTPMethod isEqualToString:@"DELETE"]) {
        [self.sessionManager DELETE:requestURLString parameters:request.parameters success:success failure:failure];
    } else {
        OWSLogError(@"Trying to perform HTTP operation with unknown method: %@", request.HTTPMethod);
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

    while (YES) {
        OWSSessionManager *_Nullable sessionManager = [self.pool lastObject];
        if (sessionManager == nil) {
            // Pool is drained.
            return [OWSSessionManager new];
        }

        [self.pool removeLastObject];

        if ([self shouldDiscardSessionManager:sessionManager]) {
            // Discard.
        } else {
            return sessionManager;
        }
    }
}

- (void)returnToPool:(OWSSessionManager *)sessionManager
{
    AssertOnDispatchQueue(NetworkManagerQueue());

    OWSAssertDebug(sessionManager);
    const NSUInteger kMaxPoolSize = 32;
    if (self.pool.count >= kMaxPoolSize || [self shouldDiscardSessionManager:sessionManager]) {
        // Discard.
        return;
    }
    [self.pool addObject:sessionManager];
}

- (BOOL)shouldDiscardSessionManager:(OWSSessionManager *)sessionManager
{
    return fabs(sessionManager.createdDate.timeIntervalSinceNow) > self.maxSessionManagerAge;
}

- (NSTimeInterval)maxSessionManagerAge
{
    // Throw away session managers every 5 minutes.
    return 5 * kMinuteInterval;
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
    return TSAccountManager.shared;
}

#pragma mark - Singleton

+ (instancetype)shared
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
#if TESTABLE_BUILD
        if (SSKDebugFlags.logCurlOnSuccess) {
            [TSNetworkManager logCurlForTask:task];
        }
#endif

        dispatch_async(NetworkManagerQueue(), ^{
            [sessionManagerPool returnToPool:sessionManager];
        });

        dispatch_async(completionQueue, ^{
            OWSLogInfo(@"%@ succeeded : %@", label, request);

            if (canUseAuth && request.shouldHaveAuthorizationHeaders) {
                [TSNetworkManager.tsAccountManager setIsDeregistered:NO];
            }

            successParam(task, responseObject);

            [OutageDetection.shared reportConnectionSuccess];
        });
    };
    TSNetworkManagerFailure failure = ^(NSURLSessionDataTask *task, NSError *error) {
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

#if TESTABLE_BUILD
+ (void)logCurlForTask:(NSURLSessionTask *)task
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
    if (task.originalRequest.HTTPBody.length > 0) {
        NSString *_Nullable contentType = task.originalRequest.allHTTPHeaderFields[@"Content-Type"];
        BOOL isJson = [contentType isEqualToString:OWSMimeTypeJson];
        BOOL isProtobuf = [contentType isEqualToString:@"application/x-protobuf"];
        if (isJson) {
            NSString *jsonBody = [[NSString alloc] initWithData:task.originalRequest.HTTPBody
                                                       encoding:NSUTF8StringEncoding];
            // We don't yet support escaping JSON.
            // If these asserts trip, we'll need to add that.
            OWSAssertDebug([jsonBody rangeOfString:@"'"].location == NSNotFound);
            [curlComponents addObject:@"--data-ascii"];
            [curlComponents addObject:[NSString stringWithFormat:@"'%@'", jsonBody]];
        } else if (isProtobuf) {
            NSData *bodyData = task.originalRequest.HTTPBody;
            NSString *filename = [NSString stringWithFormat:@"%@.tmp", NSUUID.UUID.UUIDString];

            uint8_t bodyBytes[bodyData.length];
            [bodyData getBytes:bodyBytes length:bodyData.length];
            NSMutableArray<NSString *> *echoBytes = [NSMutableArray new];
            for (NSUInteger i = 0; i < bodyData.length; i++) {
                uint8_t bodyByte = bodyBytes[i];
                [echoBytes addObject:[NSString stringWithFormat:@"\\\\x%02X", bodyByte]];
            }
            NSString *echoCommand =
                [NSString stringWithFormat:@"echo -n -e %@ > %@", [echoBytes componentsJoinedByString:@""], filename];

            OWSLogVerbose(@"curl for request: %@", echoCommand);
            [curlComponents addObject:@"--data-binary"];
            [curlComponents addObject:[NSString stringWithFormat:@"@%@", filename]];
        } else {
            OWSFailDebug(@"Unknown content type: %@", contentType);
        }
    }
    // TODO: Add support for cookies.
    // Double-quote the URL.
    [curlComponents addObject:[NSString stringWithFormat:@"\"%@\"", task.originalRequest.URL.absoluteString]];
    NSString *curlCommand = [curlComponents componentsJoinedByString:@" "];
    OWSLogVerbose(@"curl for request: %@", curlCommand);
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
    NSDate *retryAfterDate = [task retryAfterDate];

#if TESTABLE_BUILD
    [TSNetworkManager logCurlForTask:task];
#endif

    [OutageDetection.shared reportConnectionFailure];

    if (statusCode == AppExpiry.appExpiredStatusCode) {
        [AppExpiry.shared setHasAppExpiredAtCurrentVersion];
    }

    NSError *error = [self errorWithHTTPCode:statusCode
                                 description:nil
                               failureReason:nil
                          recoverySuggestion:nil
                                  retryAfter:retryAfterDate
                               fallbackError:networkError];

    switch (statusCode) {
        case 0: {
            NSError *connectivityError =
                [self errorWithHTTPCode:TSNetworkManagerErrorFailedConnection
                            description:NSLocalizedString(@"ERROR_DESCRIPTION_NO_INTERNET",
                                            @"Generic error used whenever Signal can't contact the server")
                          failureReason:networkError.localizedFailureReason
                     recoverySuggestion:NSLocalizedString(@"NETWORK_ERROR_RECOVERY", nil)
                             retryAfter:nil
                          fallbackError:networkError];
            connectivityError.isRetryable = YES;

            OWSLogWarn(@"The network request failed because of a connectivity error: %@", request);
            failureBlock(task, connectivityError);
            break;
        }
        case 400: {
            OWSLogWarn(@"The request contains an invalid parameter : %@, %@", networkError.debugDescription, request);

            error.isRetryable = NO;

            failureBlock(task, error);
            break;
        }
        case 401: {
            OWSLogWarn(@"The server returned an error about the authorization header: %@, %@",
                networkError.debugDescription,
                request);
            error.isRetryable = NO;
            [self deregisterAfterAuthErrorIfNecessary:task request:request statusCode:statusCode];
            failureBlock(task, error);
            break;
        }
        case 402: {
            error.isRetryable = NO;
            failureBlock(task, error);
            break;
        }
        case 403: {
            OWSLogWarn(
                @"The server returned an authentication failure: %@, %@", networkError.debugDescription, request);
            error.isRetryable = NO;
            [self deregisterAfterAuthErrorIfNecessary:task request:request statusCode:statusCode];
            failureBlock(task, error);
            break;
        }
        case 404: {
            OWSLogWarn(@"The requested resource could not be found: %@, %@", networkError.debugDescription, request);
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
                                                retryAfter:retryAfterDate
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
                                                retryAfter:retryAfterDate
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
                                                retryAfter:retryAfterDate
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
    if ([task.originalRequest.URL.absoluteString hasPrefix:TSConstants.textSecureServerURL]
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
                    retryAfter:(nullable NSDate *)retryAfterDate
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
    if (retryAfterDate) {
        [dict setObject:retryAfterDate forKey:TSNetworkManagerErrorRetryAfterKey];
    }

    dict[NSUnderlyingErrorKey] = fallbackError;

    return [NSError errorWithDomain:TSNetworkManagerErrorDomain code:code userInfo:dict];
}

@end

NS_ASSUME_NONNULL_END
