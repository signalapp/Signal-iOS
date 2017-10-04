//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "RemoteVideoView.h"
#import <WebRTC/RTCEAGLVideoView.h>
#import <WebRTC/RTCMTLVideoView.h>
#import <WebRTC/RTCVideoRenderer.h>
#import <PureLayout/PureLayout.h>

@interface RTCMTLVideoView (MakePrivatePublic)
+ (BOOL)isMetalAvailable;
@end

@interface RemoteVideoView () <RTCEAGLVideoViewDelegate>

@property (nonatomic, readonly) __kindof UIView<RTCVideoRenderer> *adaptee;

// Used for legacy EAGLVideoView
@property (nonatomic) CGSize remoteVideoSize;
@property (nullable, nonatomic) NSMutableArray<NSLayoutConstraint *> *remoteVideoConstraints;

@end

@implementation RemoteVideoView
//@implementation RemoteVideoViewAdapter

//protocol RemoteVideoViewAdaptee: RTCVideoRenderer {
//
//}
//
//
//#if defined(RTC_SUPPORTS_METAL)
//        if #available(iOS 9, *) {
//
//        }
//#endif
//
//        if adaptee == nil {
//            let eaglVideoView = RTCEAGLVideoView()
//            eaglVideoView.delegate = self
//            adaptee = eaglVideoView
//        }
//
//        super.init()
//    }
//}
- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

// This class is defined in objc in order to access this compile time macro
#if defined(RTC_SUPPORTS_METAL)
    if ([RTCMTLVideoView isMetalAvailable]) {
        _adaptee = [[RTCMTLVideoView alloc] initWithFrame:CGRectZero];
    }
#endif
    if (_adaptee == nil) {
        RTCEAGLVideoView *eaglVideoView = [RTCEAGLVideoView new];
        eaglVideoView.delegate = self;
        _adaptee = eaglVideoView;
    }
    
    [self addSubview:_adaptee];
    [_adaptee autoPinEdgesToSuperviewEdges];

    return self;
}

- (void)updateRemoteVideoLayout
{
//    if isMetalAvailable {
//        if #available(iOS 9, *) {
//            assert(remoteVideoView as? RTCMTLVideoView != nil)
//        } else {
//            owsFail("metal should only be available on iOS9+")
//        }
//        Logger.debug("no additional layout needed for RTCMTLVideoView")
//    } else if let videoView = remoteVideoView as? RTCEAGLVideoView {
//        NSLayoutConstraint.deactivate(self.remoteVideoConstraints)
//
//        var constraints: [NSLayoutConstraint] = []
//        // We fill the screen with the remote video. The remote video's
//        // aspect ratio may not (and in fact will very rarely) match the
//        // aspect ratio of the current device, so parts of the remote
//        // video will be hidden offscreen.
//        //
//        // It's better to trim the remote video than to adopt a letterboxed
//        // layout.
//        if remoteVideoSize.width > 0 && remoteVideoSize.height > 0 &&
//            self.view.bounds.size.width > 0 && self.view.bounds.size.height > 0 {
//
//                var remoteVideoWidth = self.view.bounds.size.width
//                var remoteVideoHeight = self.view.bounds.size.height
//                if remoteVideoSize.width / self.view.bounds.size.width > remoteVideoSize.height / self.view.bounds.size.height {
//                    remoteVideoWidth = round(self.view.bounds.size.height * remoteVideoSize.width / remoteVideoSize.height)
//                } else {
//                    remoteVideoHeight = round(self.view.bounds.size.width * remoteVideoSize.height / remoteVideoSize.width)
//                }
//                constraints.append(videoView.autoSetDimension(.width, toSize:remoteVideoWidth))
//                constraints.append(videoView.autoSetDimension(.height, toSize:remoteVideoHeight))
//                constraints += videoView.autoCenterInSuperview()
//
//                videoView.frame = CGRect(origin:CGPoint.zero,
//                                         size:CGSize(width:remoteVideoWidth,
//                                                     height:remoteVideoHeight))
//
//            } else {
//                constraints += videoView.autoPinEdgesToSuperviewEdges()
//            }
//        self.remoteVideoConstraints = constraints
//        // We need to force relayout to occur immediately (and not
//        // wait for a UIKit layout/render pass) or the remoteVideoView
//        // (which presumably is updating its CALayer directly) will
//        // ocassionally appear to have bad frames.
//        videoView.setNeedsLayout()
//        videoView.superview?.setNeedsLayout()
//        videoView.layoutIfNeeded()
//        videoView.superview?.layoutIfNeeded()
//    } else {
//        owsFail("in \(#function) with unhandled remoteVideoView type: \(remoteVideoView)")
//    }
    
    UIView *containingView = [self superview];
    if (containingView == nil) {
        DDLogDebug(@"%@ Cannot layout video view without superview", self.logTag);
        return;
    }

    // We fill the screen with the remote video. The remote video's
    // aspect ratio may not (and in fact will very rarely) match the
    // aspect ratio of the current device, so parts of the remote
    // video will be hidden offscreen.
    //
    // It's better to trim the remote video than to adopt a letterboxed
    // layout.
    // This is only required on the legacy EAGL view. The modern MetalKit
    // backed view can scale using the AspectFill content mode
    if ([self.adaptee isKindOfClass:[RTCEAGLVideoView class]]) {
        RTCEAGLVideoView *videoView = (RTCEAGLVideoView *)self.adaptee;
        [NSLayoutConstraint deactivateConstraints:self.remoteVideoConstraints];
        
        CGSize remoteVideoSize = self.remoteVideoSize;
        
        NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray new];
        if (remoteVideoSize.width > 0 && remoteVideoSize.height > 0 &&
            containingView.bounds.size.width > 0 && containingView.bounds.size.height > 0) {
                
            CGFloat remoteVideoWidth = containingView.bounds.size.width;
            CGFloat remoteVideoHeight = containingView.bounds.size.height;
            
            if (remoteVideoSize.width / containingView.bounds.size.width > remoteVideoSize.height / containingView.bounds.size.height) {
                remoteVideoWidth = round(containingView.bounds.size.height * remoteVideoSize.width / remoteVideoSize.height);
            } else {
                remoteVideoHeight = round(containingView.bounds.size.width * remoteVideoSize.height / remoteVideoSize.width);
            }
            [constraints addObject:[videoView autoSetDimension:ALDimensionWidth toSize:remoteVideoWidth]];
            [constraints addObject:[videoView autoSetDimension:ALDimensionHeight toSize:remoteVideoHeight]];
            [constraints addObjectsFromArray:[videoView autoCenterInSuperview]];
            
            videoView.frame = CGRectMake(0, 0, remoteVideoWidth, remoteVideoHeight);
                
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
}

// MARK: - RTCEAGLVideoViewDelegate

- (void)videoView:(RTCEAGLVideoView *)videoView didChangeVideoSize:(CGSize)size
{
    AssertIsOnMainThread();

    // TODO
//    if videoView != remoteVideoView {
//        return
//    }
    DDLogInfo(@"%s called", __PRETTY_FUNCTION__);
    
    self.remoteVideoSize = size;
    [self updateRemoteVideoLayout];
}

#pragma mark - RTCVideoRenderer

/** The size of the frame. */
- (void)setSize:(CGSize)size
{
    [self.adaptee setSize:size];
}

/** The frame to be displayed. */
- (void)renderFrame:(nullable RTCVideoFrame *)frame
{
    [self.adaptee renderFrame:frame];
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
