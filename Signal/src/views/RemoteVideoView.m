//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "RemoteVideoView.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <MetalKit/MetalKit.h>
#import <PureLayout/PureLayout.h>
#import <WebRTC/RTCEAGLVideoView.h>
#import <WebRTC/RTCMTLVideoView.h>
#import <WebRTC/RTCVideoRenderer.h>

NS_ASSUME_NONNULL_BEGIN

// As of RTC M61, iOS8 crashes when ending call while de-alloc'ing the EAGLVideoView
// WebRTC doesn't seem to support iOS8 - e.g. their Podfile requires iOS9+
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

@end

@implementation RemoteVideoView

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(9, 0)) {
        _videoRenderer = [NullVideoRenderer new];
    }

    if (_videoRenderer == nil) {
// This class is defined in objc in order to access this compile time macro
// Currently RTC only supports metal on 64bit machines
#if defined(RTC_SUPPORTS_METAL)
    // RTCMTLVideoView requires the MTKView class, available in the iOS9+ MetalKit framework
    if ([MTKView class]) {
        _videoRenderer = [[RTCMTLVideoView alloc] initWithFrame:CGRectZero];
    }
#endif
    }

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

NS_ASSUME_NONNULL_END
