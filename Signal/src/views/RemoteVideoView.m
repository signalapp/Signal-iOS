//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "RemoteVideoView.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <MetalKit/MetalKit.h>
#import <PureLayout/PureLayout.h>
#import <SignalCoreKit/Threading.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <WebRTC/RTCEAGLVideoView.h>
#import <WebRTC/RTCMTLVideoView.h>
#import <WebRTC/RTCVideoRenderer.h>

NS_ASSUME_NONNULL_BEGIN

@interface RemoteVideoView ()

@property (nonatomic, readonly) __kindof UIView<RTCVideoRenderer> *videoRenderer;

@end

@implementation RemoteVideoView

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    // Metal is only supported on ARM64 devices. We only support ARM64 devices,
    // with the exception being the simulator.
#if defined(__arm64__)
    RTCMTLVideoView *rtcMetalView = [[RTCMTLVideoView alloc] initWithFrame:CGRectZero];
    rtcMetalView.videoContentMode = UIDevice.currentDevice.isIPad ? UIViewContentModeScaleAspectFit : UIViewContentModeScaleAspectFill;
    _videoRenderer = rtcMetalView;
    [self addSubview:_videoRenderer];
    [_videoRenderer autoPinEdgesToSuperviewEdges];
    // We want the rendered video to go edge-to-edge.
    _videoRenderer.layoutMargins = UIEdgeInsetsZero;
    // HACK: Although RTCMTLVideo view is positioned to the top edge of the screen
    // It's inner (private) MTKView is below the status bar.
    for (UIView *subview in [_videoRenderer subviews]) {
        if ([subview isKindOfClass:[MTKView class]]) {
            [subview autoPinEdgesToSuperviewEdges];
        } else {
            OWSFailDebug(@"New subviews added to MTLVideoView. Reconsider this hack.");
        }
    }
#else
    // For simulators just set a solid background color.
    self.backgroundColor = [UIColor.blueColor colorWithAlphaComponent:0.4];
#endif

    return self;
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

@end

NS_ASSUME_NONNULL_END
