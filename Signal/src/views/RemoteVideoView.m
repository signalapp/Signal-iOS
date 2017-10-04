//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "RemoteVideoView.h"
#import <MetalKit/MetalKit.h>
#import <PureLayout/PureLayout.h>
#import <WebRTC/RTCEAGLVideoView.h>
#import <WebRTC/RTCMTLVideoView.h>
#import <WebRTC/RTCVideoRenderer.h>

@interface RTCMTLVideoView (MakePrivatePublic)
+ (BOOL)isMetalAvailable;
@end

@interface RemoteVideoView () <RTCEAGLVideoViewDelegate>

@property (nonatomic, readonly) __kindof UIView<RTCVideoRenderer> *videoRenderer;

@end

@implementation RemoteVideoView

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

// This class is defined in objc in order to access this compile time macro
// Currently RTC only supports metal on 64bit machines
#if defined(RTC_SUPPORTS_METAL)
    // RTCMTLVideoView requires the MTKView class, available in the iOS9+ MetalKit framework
    if ([MTKView class]) {
        _videoRenderer = [[RTCMTLVideoView alloc] initWithFrame:CGRectZero];
    }
#endif
    if (_videoRenderer == nil) {
        RTCEAGLVideoView *eaglVideoView = [[RTCEAGLVideoView alloc] initWithFrame:CGRectZero];
        eaglVideoView.delegate = self;
        _videoRenderer = eaglVideoView;
    }

    [self addSubview:_videoRenderer];

    _videoRenderer.layoutMargins = UIEdgeInsetsZero;
    [_videoRenderer autoPinEdgesToSuperviewEdges];

    return self;
}

#pragma mark - RTCEAGLVideoViewDelegate

- (void)videoView:(RTCEAGLVideoView *)videoView didChangeVideoSize:(CGSize)size
{
    // Do nothing. In older versions of WebRTC we used this to fit the video to fullscreen,
    // but now we use the RTCVideoRenderer.setSize.
    // However setting a delegate is *required* when using EAGL view.
}

#pragma mark - RTCVideoRenderer

/** The size of the frame. */
- (void)setSize:(CGSize)size
{
    [self.videoRenderer setSize:size];
}

/** The frame to be displayed. */
- (void)renderFrame:(nullable RTCVideoFrame *)frame
{
    [self.videoRenderer renderFrame:frame];
}

#pragma mark - Logging

+ (NSString *)logTag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)logTag
{
    return self.class.logTag;
}

@end
