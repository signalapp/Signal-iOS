//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

static void *OWSWebSocketStateObservationContext = &OWSWebSocketStateObservationContext;

extern NSNotificationName const NSNotificationWebSocketStateDidChange;

typedef NS_ENUM(NSUInteger, OWSWebSocketState) {
    OWSWebSocketStateClosed,
    OWSWebSocketStateConnecting,
    OWSWebSocketStateOpen,
};

typedef void (^TSSocketMessageSuccess)(id _Nullable responseObject);
// statusCode is zero by default, if request never made or failed.
typedef void (^TSSocketMessageFailure)(NSInteger statusCode, NSData *_Nullable responseData, NSError *error);

@class TSRequest;

@interface OWSWebSocket : NSObject

@property (nonatomic, readonly) OWSWebSocketState state;
@property (nonatomic, readonly) BOOL hasEmptiedInitialQueue;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

// If the app is in the foreground, we'll try to open the socket unless it's already
// open or connecting.
//
// If the app is in the background, we'll try to open the socket unless it's already
// open or connecting _and_ keep it open for at least N seconds.
// If the app is in the background and the socket is already open or connecting this
// might prolong how long we keep the socket open.
//
// This method can be called from any thread.
- (void)requestSocketOpen;

// This can be used to force the socket to close and re-open, if it is open.
- (void)cycleSocket;

#pragma mark - Message Sending

@property (atomic, readonly) BOOL canMakeRequests;

- (void)makeRequest:(TSRequest *)request
            success:(TSSocketMessageSuccess)success
            failure:(TSSocketMessageFailure)failure;

@end

NS_ASSUME_NONNULL_END
