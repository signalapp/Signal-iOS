//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSWebSocket.h"

NS_ASSUME_NONNULL_BEGIN

@class TSRequest;

@interface TSSocketManager : NSObject

@property (class, readonly, nonatomic) TSSocketManager *shared;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

// Returns the "best" state of any of the sockets.
//
// We surface the socket state in various places in the UI.
// We generally are trying to indicate/help resolve network
// connectivity issues.  We want to show the "best" or "highest"
// socket state of the sockets.  e.g. the UI should reflect
// "open" if any of the sockets is open.
- (OWSWebSocketState)socketState;
- (BOOL)hasEmptiedInitialQueue;

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

- (BOOL)canMakeRequests;

- (void)makeRequest:(TSRequest *)request
            success:(TSSocketMessageSuccess)success
            failure:(TSSocketMessageFailure)failure;

@end

NS_ASSUME_NONNULL_END
