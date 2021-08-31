//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const NSNotificationWebSocketStateDidChange;

typedef NS_CLOSED_ENUM(NSUInteger, OWSWebSocketType) {
    OWSWebSocketTypeIdentified,
    OWSWebSocketTypeUnidentified,
};

NSString *NSStringForOWSWebSocketType(OWSWebSocketType value);

typedef NS_CLOSED_ENUM(NSUInteger, OWSWebSocketState) {
    OWSWebSocketStateClosed,
    OWSWebSocketStateConnecting,
    OWSWebSocketStateOpen,
};

@class OWSHTTPErrorWrapper;
@class TSRequest;

@protocol HTTPResponse;
@protocol HTTPFailure;

typedef void (^TSSocketMessageSuccess)(id<HTTPResponse> response);
typedef void (^TSSocketMessageFailure)(OWSHTTPErrorWrapper *failure);

// TODO: Port to Swift.
@interface OWSWebSocket : NSObject

@property (nonatomic, readonly) OWSWebSocketType webSocketType;
@property (nonatomic, readonly) OWSWebSocketState state;
@property (nonatomic, readonly) BOOL hasEmptiedInitialQueue;
@property (nonatomic, readonly) BOOL shouldSocketBeOpen;

@property (nonatomic, readonly, class) BOOL verboseLogging;
@property (nonatomic, readonly) BOOL verboseLogging;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithWebSocketType:(OWSWebSocketType)webSocketType NS_DESIGNATED_INITIALIZER;

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

- (void)makeRequestInternal:(TSRequest *)request
                    success:(TSSocketMessageSuccess)success
                    failure:(TSSocketMessageFailure)failure;

@end

NS_ASSUME_NONNULL_END
