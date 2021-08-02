//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/RESTNetworkManager.h>
#import <SignalServiceKit/OWSQueues.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSRequest.h>

NS_ASSUME_NONNULL_BEGIN

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

@property (nonatomic) NSMutableArray<RESTSessionManager *> *pool;

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

- (RESTSessionManager *)get
{
    AssertOnDispatchQueue(NetworkManagerQueue());
    
    while (YES) {
        RESTSessionManager *_Nullable sessionManager = [self.pool lastObject];
        if (sessionManager == nil) {
            // Pool is drained.
            return [RESTSessionManager new];
        }
        
        [self.pool removeLastObject];
        
        if ([self shouldDiscardSessionManager:sessionManager]) {
            // Discard.
        } else {
            return sessionManager;
        }
    }
}

- (void)returnToPool:(RESTSessionManager *)sessionManager
{
    AssertOnDispatchQueue(NetworkManagerQueue());
    
    OWSAssertDebug(sessionManager);
    const NSUInteger kMaxPoolSize = CurrentAppContext().isNSE ? 5 : 32;
    if (self.pool.count >= kMaxPoolSize || [self shouldDiscardSessionManager:sessionManager]) {
        // Discard.
        return;
    }
    [self.pool addObject:sessionManager];
}

- (BOOL)shouldDiscardSessionManager:(RESTSessionManager *)sessionManager
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

@interface RESTNetworkManager ()

// These properties should only be accessed on serialQueue.
@property (atomic, readonly) OWSSessionManagerPool *udSessionManagerPool;
@property (atomic, readonly) OWSSessionManagerPool *nonUdSessionManagerPool;

@end

#pragma mark -

@implementation RESTNetworkManager

- (instancetype)init
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
    completionQueue:(dispatch_queue_t)completionQueue
            success:(RESTNetworkManagerSuccess)success
            failure:(RESTNetworkManagerFailure)failure
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
                success:(RESTNetworkManagerSuccess)successParam
                failure:(RESTNetworkManagerFailure)failureParam
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
    RESTSessionManager *sessionManager = [sessionManagerPool get];
    
    RESTNetworkManagerSuccess success = ^(id<HTTPResponse> response) {
#if TESTABLE_BUILD
        if (SSKDebugFlags.logCurlOnSuccess) {
            [HTTPUtils logCurlForURLRequest:request];
        }
#endif
        
        dispatch_async(NetworkManagerQueue(), ^{
            [sessionManagerPool returnToPool:sessionManager];
        });
        
        dispatch_async(completionQueue, ^{
            OWSLogInfo(@"%@ succeeded : %@", label, request);
            
            if (canUseAuth && request.shouldHaveAuthorizationHeaders) {
                [RESTNetworkManager.tsAccountManager setIsDeregistered:NO];
            }
            
            successParam(response);
            
            [OutageDetection.shared reportConnectionSuccess];
        });
    };
    RESTNetworkManagerFailure failure = ^(OWSHTTPErrorWrapper *errorWrapper) {
        dispatch_async(NetworkManagerQueue(), ^{
            [sessionManagerPool returnToPool:sessionManager];
        });

        [RESTNetworkManager
            handleNetworkFailure:^(OWSHTTPErrorWrapper *errorWrapper) {
                dispatch_async(completionQueue, ^{ failureParam(errorWrapper); });
            }
                         request:request
                    errorWrapper:errorWrapper];
    };
    
    [sessionManager performRequest:request
                        canUseAuth:canUseAuth
                           success:success
                           failure:failure];
}

+ (void)handleNetworkFailure:(RESTNetworkManagerFailure)failureBlock
                     request:(TSRequest *)request
                errorWrapper:(OWSHTTPErrorWrapper *)errorWrapper
{
    OWSAssertDebug(failureBlock);
    OWSAssertDebug(request);
    OWSAssertDebug(errorWrapper);
    
    failureBlock(errorWrapper);
}

@end

NS_ASSUME_NONNULL_END
