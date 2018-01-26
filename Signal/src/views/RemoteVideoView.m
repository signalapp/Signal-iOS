//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
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

// As of RTC M61, iOS8 crashes when ending calls while de-alloc'ing the EAGLVideoView.
// WebRTC doesn't seem to support iOS8 - e.g. their Podfile requires iOS9+, and they
// unconditionally require MetalKit on a 64bit iOS8 device (which crashes).
// Until WebRTC supports iOS8, we show a "upgrade iOS to see remote video" view
// to our few remaining iOS8 users
@interface NullVideoRenderer : UIView <RTCVideoRenderer>

@end

@implementation NullVideoRenderer

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (!self) {
        return self;
    }

    self.backgroundColor = UIColor.blackColor;

    UILabel *label = [UILabel new];
    label.numberOfLines = 0;
    label.text
        = NSLocalizedString(@"CALL_REMOTE_VIDEO_DISABLED", @"Text shown on call screen in place of remote video");
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont ows_boldFontWithSize:ScaleFromIPhone5(20)];
    label.textColor = UIColor.whiteColor;
    label.lineBreakMode = NSLineBreakByWordWrapping;

    [self addSubview:label];
    [label autoVCenterInSuperview];
    [label autoPinWidthToSuperviewWithMargin:ScaleFromIPhone5(16)];

    return self;
}

#pragma mark - RTCVideoRenderer

/** The size of the frame. */
- (void)setSize:(CGSize)size
{
    // Do nothing.
}

/** The frame to be displayed. */
- (void)renderFrame:(nullable RTCVideoFrame *)frame
{
    // Do nothing.
}

@end

@interface RemoteVideoView () <RTCEAGLVideoViewDelegate>

@property (nonatomic, readonly) __kindof UIView<RTCVideoRenderer> *videoRenderer;

// Used for legacy EAGLVideoView
@property (nullable, nonatomic) NSMutableArray<NSLayoutConstraint *> *remoteVideoConstraints;

@end

@implementation RemoteVideoView

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    // On iOS8: prints a message saying the feature is unavailable.
    if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(9, 0)) {
        _videoRenderer = [NullVideoRenderer new];
        [self addSubview:_videoRenderer];
        [_videoRenderer autoPinEdgesToSuperviewEdges];
    }

// Currently RTC only supports metal on 64bit machines
#if defined(RTC_SUPPORTS_METAL)
    // On 64-bit, iOS9+: uses the MetalKit backed view for improved battery/rendering performance.
    if (_videoRenderer == nil) {

        // It is insufficient to check the RTC_SUPPORTS_METAL macro to determine Metal support.
        // RTCMTLVideoView requires the MTKView class, available only in iOS9+
        // So check that it exists before proceeding.
        if ([MTKView class]) {
            _videoRenderer = [[RTCMTLVideoView alloc] initWithFrame:CGRectZero];
            [self addSubview:_videoRenderer];
            [_videoRenderer autoPinEdgesToSuperviewEdges];
            // HACK: Although RTCMTLVideo view is positioned to the top edge of the screen
            // It's inner (private) MTKView is below the status bar.
            for (UIView *subview in [_videoRenderer subviews]) {
                if ([subview isKindOfClass:[MTKView class]]) {
                    [NSLayoutConstraint autoSetPriority:UILayoutPriorityRequired
                                         forConstraints:^{
                                             [subview autoPinEdgesToSuperviewEdges];
                                         }];
                } else {
                    OWSFail(@"New subviews added to MTLVideoView. Reconsider this hack.");
                }
            }
        }
    }
#elif defined(__arm64__)
    // Canary incase the upstream RTC_SUPPORTS_METAL macro changes semantics
    OWSFail(@"should only use legacy video view on 32bit systems");
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
        OWSFail(@"Illegal video height: %f", remoteVideoSize.height);
        return;
    }

    CGFloat aspectRatio = remoteVideoSize.width / remoteVideoSize.height;

    DDLogVerbose(@"%@ Remote video size: width: %f height: %f ratio: %f",
        self.logTag,
        remoteVideoSize.width,
        remoteVideoSize.height,
        aspectRatio);

    UIView *containingView = self.superview;
    if (containingView == nil) {
        DDLogDebug(@"%@ Cannot layout video view without superview", self.logTag);
        return;
    }

    if (![self.videoRenderer isKindOfClass:[RTCEAGLVideoView class]]) {
        OWSFail(@"%@ Unexpected video renderer: %@", self.logTag, self.videoRenderer);
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

    self.remoteVideoConstraints = constraints;
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
