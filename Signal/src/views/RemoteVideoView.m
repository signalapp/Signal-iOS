//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "RemoteVideoView.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <MetalKit/MetalKit.h>
#import <PureLayout/PureLayout.h>
#import <SignalServiceKit/Threading.h>
#import <WebRTC/RTCEAGLVideoView.h>
#import <WebRTC/RTCMTLVideoView.h>
#import <WebRTC/RTCVideoRenderer.h>

NS_ASSUME_NONNULL_BEGIN

@interface RemoteVideoView () <RTCEAGLVideoViewDelegate>

@property (nonatomic, readonly) __kindof UIView<RTCVideoRenderer> *videoRenderer;

// Used for legacy EAGLVideoView
@property (nullable, nonatomic) NSArray<NSLayoutConstraint *> *remoteVideoConstraints;

@end

@implementation RemoteVideoView

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _remoteVideoConstraints = @[];

// Currently RTC only supports metal on 64bit machines
#if defined(RTC_SUPPORTS_METAL)
    // On 64-bit, iOS9+: uses the MetalKit backed view for improved battery/rendering performance.
    if (_videoRenderer == nil) {

        // It is insufficient to check the RTC_SUPPORTS_METAL macro to determine Metal support.
        // RTCMTLVideoView requires the MTKView class, available only in iOS9+
        // So check that it exists before proceeding.
        if ([MTKView class]) {
            RTCMTLVideoView *rtcMetalView = [[RTCMTLVideoView alloc] initWithFrame:CGRectZero];
            rtcMetalView.videoContentMode = UIViewContentModeScaleAspectFill;
            _videoRenderer = rtcMetalView;
            [self addSubview:_videoRenderer];
            [_videoRenderer autoPinEdgesToSuperviewEdges];
            // HACK: Although RTCMTLVideo view is positioned to the top edge of the screen
            // It's inner (private) MTKView is below the status bar.
            for (UIView *subview in [_videoRenderer subviews]) {
                if ([subview isKindOfClass:[MTKView class]]) {
                    [subview autoPinEdgesToSuperviewEdges];
                } else {
                    OWSFailDebug(@"New subviews added to MTLVideoView. Reconsider this hack.");
                }
            }
        }
    }
#elif defined(__arm64__)
    // Canary incase the upstream RTC_SUPPORTS_METAL macro changes semantics
    OWSFailDebug(@"should only use legacy video view on 32bit systems");
#endif

    // On 32-bit iOS9+ systems, use the legacy EAGL backed view.
    if (_videoRenderer == nil) {
        RTCEAGLVideoView *eaglVideoView = [RTCEAGLVideoView new];
        eaglVideoView.delegate = self;
        _videoRenderer = eaglVideoView;
        [self addSubview:_videoRenderer];
        // Pinning legacy RTCEAGL view discards aspect ratio.
        // So we have a more verbose layout in the RTCEAGLVideoViewDelegate methods
        // [_videoRenderer autoPinEdgesToSuperviewEdges];
    }

    // We want the rendered video to go edge-to-edge.
    _videoRenderer.layoutMargins = UIEdgeInsetsZero;

    return self;
}

#pragma mark - RTCVideoRenderer

/** The size of the frame. */
- (void)setSize:(CGSize)size
{
    [self.videoRenderer setSize:size];
}

#pragma mark - RTCEAGLVideoViewDelegate

- (void)videoView:(RTCEAGLVideoView *)videoView didChangeVideoSize:(CGSize)remoteVideoSize
{
    OWSAssertIsOnMainThread();
    if (remoteVideoSize.height <= 0) {
        OWSFailDebug(@"Illegal video height: %f", remoteVideoSize.height);
        return;
    }

    CGFloat aspectRatio = remoteVideoSize.width / remoteVideoSize.height;

    OWSLogVerbose(@"Remote video size: width: %f height: %f ratio: %f",
        remoteVideoSize.width,
        remoteVideoSize.height,
        aspectRatio);

    UIView *containingView = self.superview;
    if (containingView == nil) {
        OWSLogDebug(@"Cannot layout video view without superview");
        return;
    }

    if (![self.videoRenderer isKindOfClass:[RTCEAGLVideoView class]]) {
        OWSFailDebug(@"Unexpected video renderer: %@", self.videoRenderer);
        return;
    }

    [NSLayoutConstraint deactivateConstraints:self.remoteVideoConstraints];

    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray new];
    if (remoteVideoSize.width > 0 && remoteVideoSize.height > 0 && containingView.bounds.size.width > 0
        && containingView.bounds.size.height > 0) {

        // to approximate "scale to fill" contentMode
        // - Pin aspect ratio
        // - Width and height is *at least* as wide as superview
        [constraints addObject:[videoView autoPinToAspectRatio:aspectRatio]];
        [constraints addObject:[videoView autoSetDimension:ALDimensionWidth
                                                    toSize:containingView.width
                                                  relation:NSLayoutRelationGreaterThanOrEqual]];
        [constraints addObject:[videoView autoSetDimension:ALDimensionHeight
                                                    toSize:containingView.height
                                                  relation:NSLayoutRelationGreaterThanOrEqual]];
        [constraints addObjectsFromArray:[videoView autoCenterInSuperview]];

        // Low priority constraints force view to be no larger than necessary.
        [NSLayoutConstraint autoSetPriority:UILayoutPriorityDefaultLow
                             forConstraints:^{
                                 [constraints addObjectsFromArray:[videoView autoPinEdgesToSuperviewEdges]];
                             }];

    } else {
        [constraints addObjectsFromArray:[videoView autoPinEdgesToSuperviewEdges]];
    }

    self.remoteVideoConstraints = [constraints copy];
    // We need to force relayout to occur immediately (and not
    // wait for a UIKit layout/render pass) or the remoteVideoView
    // (which presumably is updating its CALayer directly) will
    // ocassionally appear to have bad frames.
    [videoView setNeedsLayout];
    [[videoView superview] setNeedsLayout];
    [videoView layoutIfNeeded];
    [[videoView superview] layoutIfNeeded];
}

/** The frame to be displayed. */
- (void)renderFrame:(nullable RTCVideoFrame *)frame
{
    [self.videoRenderer renderFrame:frame];
}

@end

NS_ASSUME_NONNULL_END
