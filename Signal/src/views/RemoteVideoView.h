//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <WebRTC/RTCVideoRenderer.h>

/**
 * Drives the full screen remote video, this class is backed by either the modern MetalKit backed view on supported
 * systems or the leagacy EAGL view. MetalKit is supported on 64bit systems running iOS8 or newer.
 */
@interface RemoteVideoView : UIView <RTCVideoRenderer>

- (void)updateRemoteVideoLayout;

@end
