//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <WebRTC/RTCVideoRenderer.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Drives the full screen remote video. This is *not* a swift class
 * so we can take advantage of some compile time constants from WebRTC
 */
@interface RemoteVideoView : UIView <RTCVideoRenderer>

@property (atomic) BOOL isGroupCall;

@end

NS_ASSUME_NONNULL_END
