//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "RemoteVideoView.h"
#import <MetalKit/MetalKit.h>
#import <PureLayout/PureLayout.h>
#import <SignalCoreKit/Threading.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalUI/UIView+SignalUI.h>
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
@property (nonatomic) BOOL applyDefaultRendererConfigurationOnNextFrame;

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

    [self applyDefaultRendererConfiguration];

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
        if (self.applyDefaultRendererConfigurationOnNextFrame) {
            self.applyDefaultRendererConfigurationOnNextFrame = NO;
            [self applyDefaultRendererConfiguration];
        }

        // In certain cases, rotate the video so it's always right side up in landscape.
        // We only allow portrait orientation in the calling views on iPhone so we don't
        // get this for free.
        BOOL shouldOverrideRotation;
        if (UIDevice.currentDevice.isIPad || !self.isFullScreen) {
            // iPad allows all orientations so we can skip this.
            // Non-full-screen views are part of a portrait-locked UI (e.g. the group call grid)
            // and rotating the video without rotating the UI would look weird.
            shouldOverrideRotation = NO;
        } else if (self.isGroupCall) {
            // For speaker view in a group call, keep screenshares right-side up.
            shouldOverrideRotation = self.isScreenShare;
        } else {
            // For a 1:1 call, always keep video right-side up.
            shouldOverrideRotation = YES;
        }

        BOOL isLandscape;
        if (shouldOverrideRotation) {
            switch (UIDevice.currentDevice.orientation) {
                case UIDeviceOrientationPortrait:
                case UIDeviceOrientationPortraitUpsideDown:
                    // We don't have to do anything, the renderer will automatically
                    // make sure it's right-side-up.
                    isLandscape = NO;
                    self.metalRenderer.rotationOverride = nil;
                    break;
                case UIDeviceOrientationLandscapeLeft:
                    isLandscape = YES;
                    switch (frame.rotation) {
                        // Portrait upside-down
                        case RTCVideoRotation_270:
                            self.metalRenderer.rotationOverride = @(RTCVideoRotation_0);
                            break;
                        // Portrait
                        case RTCVideoRotation_90:
                            self.metalRenderer.rotationOverride = @(RTCVideoRotation_180);
                            break;
                        // Landscape right
                        case RTCVideoRotation_180:
                            self.metalRenderer.rotationOverride = @(RTCVideoRotation_270);
                            break;
                        // Landscape left
                        case RTCVideoRotation_0:
                            self.metalRenderer.rotationOverride = @(RTCVideoRotation_90);
                            break;
                    }
                    break;
                case UIDeviceOrientationLandscapeRight:
                    isLandscape = YES;
                    switch (frame.rotation) {
                        // Portrait upside-down
                        case RTCVideoRotation_270:
                            self.metalRenderer.rotationOverride = @(RTCVideoRotation_180);
                            break;
                        // Portrait
                        case RTCVideoRotation_90:
                            self.metalRenderer.rotationOverride = @(RTCVideoRotation_0);
                            break;
                        // Landscape right
                        case RTCVideoRotation_180:
                            self.metalRenderer.rotationOverride = @(RTCVideoRotation_90);
                            break;
                        // Landscape left
                        case RTCVideoRotation_0:
                            self.metalRenderer.rotationOverride = @(RTCVideoRotation_270);
                            break;
                    }
                    break;
                default:
                    // Do nothing if we're face down, up, etc.
                    // Assume we're already set up for the correct orientation.
                    return;
            }
        } else {
            self.metalRenderer.rotationOverride = nil;
            isLandscape = self.width > self.height;
        }

        BOOL remoteIsLandscape = frame.rotation == RTCVideoRotation_180 || frame.rotation == RTCVideoRotation_0;

        BOOL isSquarish = (MAX(self.width, self.height) / MIN(self.width, self.height)) <= 1.2;

        // If we're both in the same orientation, let the video fill the screen.
        // Otherwise, fit the video to the screen size respecting the aspect ratio.
        if ((isLandscape == remoteIsLandscape || isSquarish) && !self.isScreenShare) {
            self.metalRenderer.videoContentMode = UIViewContentModeScaleAspectFill;
        } else {
            self.metalRenderer.videoContentMode = UIViewContentModeScaleAspectFit;
        }
    });
#endif
}

- (void)setIsScreenShare:(BOOL)isScreenShare
{
    if (isScreenShare != _isScreenShare) {
        self.applyDefaultRendererConfigurationOnNextFrame = YES;
    }

    _isScreenShare = isScreenShare;
}

- (void)setIsGroupCall:(BOOL)isGroupCall
{
    if (isGroupCall != _isGroupCall) {
        self.applyDefaultRendererConfigurationOnNextFrame = YES;
    }

    _isGroupCall = isGroupCall;
}

- (void)setIsFullScreen:(BOOL)isFullScreen
{
    if (isFullScreen != _isFullScreen) {
        self.applyDefaultRendererConfigurationOnNextFrame = YES;
    }

    _isFullScreen = isFullScreen;
}

- (void)applyDefaultRendererConfiguration
{
#if DEVICE_SUPPORTS_METAL
    if (UIDevice.currentDevice.isIPad) {
        self.metalRenderer.videoContentMode = UIViewContentModeScaleAspectFit;
        self.metalRenderer.rotationOverride = nil;
    } else {
        self.metalRenderer.videoContentMode = UIViewContentModeScaleAspectFill;
        self.metalRenderer.rotationOverride = nil;
    }
#endif
}

@end

NS_ASSUME_NONNULL_END
