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
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <WebRTC/RTCEAGLVideoView.h>
#import <WebRTC/RTCMTLVideoView.h>
#import <WebRTC/RTCVideoFrame.h>
#import <WebRTC/RTCVideoRenderer.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

@interface RemoteVideoView ()

@property (nonatomic, nullable) __kindof UIView<RTCVideoRenderer> *videoRenderer;

@end

#if COREVIDEO_SUPPORTS_METAL

@interface RemoteVideoView (Metal) <RTCVideoViewDelegate>

@property (nonatomic, readonly, nullable) RTCMTLVideoView *metalRenderer;

- (void)setupMetalRenderer;

@end

@implementation RemoteVideoView (Metal)

- (void)setupMetalRenderer
{
    RTCMTLVideoView *rtcMetalView = [[RTCMTLVideoView alloc] initWithFrame:CGRectZero];
    rtcMetalView.delegate = self;
    self.videoRenderer = rtcMetalView;
    [self addSubview:rtcMetalView];
    [rtcMetalView autoPinEdgesToSuperviewEdges];
    // We want the rendered video to go edge-to-edge.
    rtcMetalView.layoutMargins = UIEdgeInsetsZero;
    // HACK: Although RTCMTLVideo view is positioned to the top edge of the screen
    // It's inner (private) MTKView is below the status bar.
    for (UIView *subview in [rtcMetalView subviews]) {
        if ([subview isKindOfClass:[MTKView class]]) {
            [subview autoPinEdgesToSuperviewEdges];
        } else {
            OWSFailDebug(@"New subviews added to MTLVideoView. Reconsider this hack.");
        }
    }

    // We're always portrait on iPhone
    if (!UIDevice.currentDevice.isIPad) {
        self.metalRenderer.videoContentMode = UIViewContentModeScaleAspectFill;
        self.metalRenderer.rotationOverride = @(RTCVideoRotation_90);
    }
}

- (nullable RTCMTLVideoView *)metalRenderer
{
    return (RTCMTLVideoView *)self.videoRenderer;
}

#pragma mark - RTCVideoViewDelegate

- (void)videoView:(id<RTCVideoRenderer>)videoView didChangeVideoSize:(CGSize)size
{
    if (!UIDevice.currentDevice.isIPad) {
        // We don't rotate the device while this view is rendered on iPhone,
        // so we don't need to adjust the content mode.
        return;
    }

    CGSize currentWindowSize = CurrentAppContext().frame.size;
    BOOL isLandscape = currentWindowSize.width > currentWindowSize.height;
    BOOL remoteIsLandscape = size.width > size.height;

    // If we're both in the same orientation, let the video fill the screen.
    // Otherwise, fit the video to the screen size respecting the aspect ratio.
    if (isLandscape == remoteIsLandscape) {
        self.metalRenderer.videoContentMode = UIViewContentModeScaleAspectFill;
    } else {
        self.metalRenderer.videoContentMode = UIViewContentModeScaleAspectFit;
    }
}

@end

#endif

#pragma mark -

@implementation RemoteVideoView

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

#if COREVIDEO_SUPPORTS_METAL
    [self setupMetalRenderer];
#endif

    // Metal is not supported on the simulator, so we just set a
    // background color for debugging purposes.
    if (Platform.isSimulator) {
        // For simulators just set a solid background color.
        self.backgroundColor = [UIColor.blueColor colorWithAlphaComponent:0.4];
    } else {
        OWSAssertDebug(self.videoRenderer);
    }

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
