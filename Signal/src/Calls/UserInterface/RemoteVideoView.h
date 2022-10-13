//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <WebRTC/RTCVideoRenderer.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Drives the full screen remote video. This is *not* a swift class
 * so we can take advantage of some compile time constants from WebRTC
 */
@interface RemoteVideoView : UIView <RTCVideoRenderer>

@property (nonatomic) BOOL isGroupCall;
@property (nonatomic) BOOL isScreenShare;
@property (nonatomic) BOOL isFullScreen;

@end

NS_ASSUME_NONNULL_END
