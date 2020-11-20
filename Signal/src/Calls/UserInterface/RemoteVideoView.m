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

#if defined(__arm64__)
#define DEVICE_SUPPORTS_METAL 1
#else
#define DEVICE_SUPPORTS_METAL 0
#endif

#pragma mark -

@interface RemoteVideoView ()

@property (nonatomic, nullable) __kindof UIView<RTCVideoRenderer> *videoRenderer;

@end

#if DEVICE_SUPPORTS_METAL

@interface RemoteVideoView (Metal)

@property (nonatomic, readonly, nullable) RTCMTLVideoView *metalRenderer;

- (void)setupMetalRenderer;

@end

@implementation RemoteVideoView (Metal)

- (void)setupMetalRenderer
{
    RTCMTLVideoView *rtcMetalView = [[RTCMTLVideoView alloc] initWithFrame:CGRectZero];
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

#if DEVICE_SUPPORTS_METAL
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

#if DEVICE_SUPPORTS_METAL
    DispatchMainThreadSafe(^{
        if (UIDevice.currentDevice.isIPad || self.isGroupCall) {
            BOOL isLandscape = self.width > self.height;
            BOOL remoteIsLandscape = frame.rotation == RTCVideoRotation_180 || frame.rotation == RTCVideoRotation_0;

            BOOL isSquarish = (MAX(self.width, self.height) / MIN(self.width, self.height)) <= 1.2;

            self.metalRenderer.rotationOverride = nil;

            // If we're both in the same orientation, let the video fill the screen.
            // Otherwise, fit the video to the screen size respecting the aspect ratio.
            if (isLandscape == remoteIsLandscape || isSquarish) {
                self.metalRenderer.videoContentMode = UIViewContentModeScaleAspectFill;
            } else {
                self.metalRenderer.videoContentMode = UIViewContentModeScaleAspectFit;
            }
        } else {
            // iPhones are locked to portrait mode. However, we want both
            // portrait and portrait upside-down to be right side up in portrait.
            // We want both landscape left and landscape right to be right side
            // up in landscape. This means, sometimes we force the rotation to
            // portrait, and sometimes we force the rotation to portrait upside
            // down depending on the orientation of the incoming frames AND
            // the device's current orientation, so that from the user's perspective
            // everything always looks right-side-up.
            switch (frame.rotation) {
                    // Portrait upside-down
                case RTCVideoRotation_270:
                    // Portrait upside down renders in portrait
                    self.metalRenderer.rotationOverride = @(RTCVideoRotation_270);
                    break;
                    // Portrait
                case RTCVideoRotation_90:
                    // Portrait renders in portrait
                    self.metalRenderer.rotationOverride = @(RTCVideoRotation_90);
                    break;
                    // Landscape right
                case RTCVideoRotation_180:
                    // If the device is in landscape left, flip upside down
                    if (UIDevice.currentDevice.orientation == UIDeviceOrientationLandscapeLeft) {
                        self.metalRenderer.rotationOverride = @(RTCVideoRotation_270);
                    } else if (UIDevice.currentDevice.orientation == UIDeviceOrientationLandscapeRight) {
                        self.metalRenderer.rotationOverride = @(RTCVideoRotation_90);
                    }
                    break;
                    // Landscape left
                case RTCVideoRotation_0:
                    // If the device is in landscape right, flip upside down
                    if (UIDevice.currentDevice.orientation == UIDeviceOrientationLandscapeRight) {
                        self.metalRenderer.rotationOverride = @(RTCVideoRotation_270);
                    } else if (UIDevice.currentDevice.orientation == UIDeviceOrientationLandscapeLeft) {
                        self.metalRenderer.rotationOverride = @(RTCVideoRotation_90);
                    }
                    break;
            }
        }
    });
#endif
}

@end

NS_ASSUME_NONNULL_END
