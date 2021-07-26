//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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
