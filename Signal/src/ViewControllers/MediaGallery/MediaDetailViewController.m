//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "MediaDetailViewController.h"
#import "ConversationViewController.h"
#import "Signal-Swift.h"
#import <AVKit/AVKit.h>
#import <MediaPlayer/MPMoviePlayerViewController.h>
#import <MediaPlayer/MediaPlayer.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/NSData+Image.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSInteraction.h>
#import <SignalUI/AttachmentSharing.h>
#import <SignalUI/UIUtil.h>
#import <SignalUI/UIView+SignalUI.h>
#import <YYImage/YYImage.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

@interface MediaDetailViewController () <UIScrollViewDelegate,
    UIGestureRecognizerDelegate,
    PlayerProgressBarDelegate,
    OWSVideoPlayerDelegate,
    LoopingVideoViewDelegate,
    VideoPlayerViewDelegate>

@property (nonatomic) UIScrollView *scrollView;
@property (nonatomic) UIView *mediaView;
@property (nonatomic) UIView *replacingView;

@property (nonatomic) TSAttachmentStream *attachmentStream;
@property (nonatomic, nullable) UIImage *image;

@property (nonatomic, nullable) OWSVideoPlayer *videoPlayer;
@property (nonatomic, nullable) UIView *playVideoButton;
@property (nonatomic, nullable) PlayerProgressBar *videoProgressBar;
@property (nonatomic, nullable) UIBarButtonItem *videoPlayBarButton;
@property (nonatomic, nullable) UIBarButtonItem *videoPauseBarButton;

@property (nonatomic, nullable) NSLayoutConstraint *mediaViewBottomConstraint;
@property (nonatomic, nullable) NSLayoutConstraint *mediaViewLeadingConstraint;
@property (nonatomic, nullable) NSLayoutConstraint *mediaViewTopConstraint;
@property (nonatomic, nullable) NSLayoutConstraint *mediaViewTrailingConstraint;

@property (nonatomic) BOOL shouldAutoPlayVideo;
@property (nonatomic) BOOL hasAutoPlayedVideo;
@property (nonatomic) CGFloat lastKnownScrollViewWidth;

@end

#pragma mark -

@implementation MediaDetailViewController

- (void)dealloc
{
    [self stopAnyVideo];
}

- (instancetype)initWithGalleryItemBox:(GalleryItemBox *)galleryItemBox shouldAutoPlayVideo:(BOOL)shouldAutoPlayVideo
{
    self = [super init];
    if (!self) {
        return self;
    }

    _galleryItemBox = galleryItemBox;
    self.shouldAutoPlayVideo = shouldAutoPlayVideo;

    // We cache the image data in case the attachment stream is deleted.
    self.image = [galleryItemBox.attachmentStream thumbnailImageLargeSync];

    return self;
}

- (TSAttachmentStream *)attachmentStream
{
    return self.galleryItemBox.attachmentStream;
}

- (BOOL)isVideo
{
    return self.attachmentStream.isVideo && !self.attachmentStream.isLoopingVideo;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor clearColor];

    [self updateContents];
}

- (void)viewWillAppear:(BOOL)animated
{
    OWSAssertIsOnMainThread();
    
    [super viewWillAppear:animated];
    [self resetMediaFrame];
    
    [self updateZoomScaleAndConstraints];
    self.scrollView.zoomScale = self.scrollView.minimumZoomScale;
}

- (void)viewDidAppear:(BOOL)animated
{
    OWSAssertIsOnMainThread();

    [super viewDidAppear:animated];

    if (self.isVideo && self.shouldAutoPlayVideo && !self.hasAutoPlayedVideo) {
        [self playVideo];
        self.hasAutoPlayedVideo = YES;
    }
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    [self updateZoomScaleAndConstraints];

    // In iOS multi-tasking, the size of root view (and hence the scroll view)
    // is set later, after viewWillAppear, etc.  Therefore we need to reset the
    // zoomScale to the default whenever the scrollView width changes.
    const CGFloat tolerance = 0.001f;
    if (fabs(self.lastKnownScrollViewWidth - self.scrollView.frame.size.width) > tolerance) {
        self.scrollView.zoomScale = self.scrollView.minimumZoomScale;
    }
    self.lastKnownScrollViewWidth = self.scrollView.frame.size.width;
}

- (void)zoomOutAnimated:(BOOL)isAnimated
{
    if (self.scrollView.zoomScale != self.scrollView.minimumZoomScale) {
        [self.scrollView setZoomScale:self.scrollView.minimumZoomScale animated:isAnimated];
    }
}

#pragma mark - Initializers

- (void)updateContents
{
    [self.mediaView removeFromSuperview];
    [self.scrollView removeFromSuperview];
    [self.playVideoButton removeFromSuperview];
    [self.videoProgressBar removeFromSuperview];

    UIScrollView *scrollView = [UIScrollView new];
    [self.view addSubview:scrollView];
    self.scrollView = scrollView;
    scrollView.delegate = self;

    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.decelerationRate = UIScrollViewDecelerationRateFast;

    [scrollView contentInsetAdjustmentBehavior];

    [scrollView autoPinEdgesToSuperviewEdges];

    if (self.attachmentStream.isLoopingVideo) {
        if (self.attachmentStream.isValidVideo) {
            self.mediaView = [self buildLoopingVideoPlayerView];
        } else {
            self.mediaView = [UIView new];
            self.mediaView.backgroundColor = Theme.washColor;
        }
    } else if (self.attachmentStream.shouldBeRenderedByYY) {
        if (self.attachmentStream.isValidImage) {
            YYImage *animatedGif = [YYImage imageWithContentsOfFile:self.attachmentStream.originalFilePath];
            YYAnimatedImageView *animatedView = [YYAnimatedImageView new];
            animatedView.image = animatedGif;
            self.mediaView = animatedView;
        } else {
            self.mediaView = [UIView new];
            self.mediaView.backgroundColor = Theme.washColor;
        }
    } else if (!self.image) {
        // Still loading thumbnail.
        self.mediaView = [UIView new];
        self.mediaView.backgroundColor = Theme.washColor;
    } else if (self.isVideo) {
        if (self.attachmentStream.isValidVideo) {
            self.mediaView = [self buildVideoPlayerView];
        } else {
            self.mediaView = [UIView new];
            self.mediaView.backgroundColor = Theme.washColor;
        }
    } else {
        // Present the static image using standard UIImageView
        UIImageView *imageView = [[UIImageView alloc] initWithImage:self.image];
        self.mediaView = imageView;
    }

    OWSAssertDebug(self.mediaView);

    // We add these gestures to mediaView rather than
    // the root view so that interacting with the video player
    // progress bar doesn't trigger any of these gestures.
    [self addGestureRecognizersToView:self.mediaView];

    [scrollView addSubview:self.mediaView];
    self.mediaViewLeadingConstraint = [self.mediaView autoPinEdgeToSuperviewEdge:ALEdgeLeading];
    self.mediaViewTopConstraint = [self.mediaView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    self.mediaViewTrailingConstraint = [self.mediaView autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    self.mediaViewBottomConstraint = [self.mediaView autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    self.mediaView.contentMode = UIViewContentModeScaleAspectFit;
    self.mediaView.userInteractionEnabled = YES;
    self.mediaView.clipsToBounds = YES;
    self.mediaView.layer.allowsEdgeAntialiasing = YES;
    self.mediaView.translatesAutoresizingMaskIntoConstraints = NO;

    // Use trilinear filters for better scaling quality at
    // some performance cost.
    self.mediaView.layer.minificationFilter = kCAFilterTrilinear;
    self.mediaView.layer.magnificationFilter = kCAFilterTrilinear;

    if (self.isVideo) {
        PlayerProgressBar *videoProgressBar = [PlayerProgressBar new];
        videoProgressBar.delegate = self;
        videoProgressBar.player = self.videoPlayer.avPlayer;

        // We hide the progress bar until either:
        // 1. Video completes playing
        // 2. User taps the screen
        videoProgressBar.hidden = YES;

        self.videoProgressBar = videoProgressBar;
        [self.view addSubview:videoProgressBar];
        [videoProgressBar autoPinWidthToSuperview];

        CGFloat kVideoProgressBarHeight = 44;
        [videoProgressBar autoPinToTopLayoutGuideOfViewController:self withInset:kVideoProgressBarHeight];
        [videoProgressBar autoSetDimension:ALDimensionHeight toSize:kVideoProgressBarHeight];

        __weak MediaDetailViewController *weakSelf = self;
        OWSButton *playVideoButton = [[OWSButton alloc] initWithBlock:^{ [weakSelf playVideo]; }];
        self.playVideoButton = playVideoButton;
        [self.view addSubview:playVideoButton];

        OWSLayerView *playVideoCircleView = [OWSLayerView circleView];
        playVideoCircleView.backgroundColor = [UIColor.ows_whiteColor colorWithAlphaComponent:0.75f];
        playVideoCircleView.userInteractionEnabled = NO;
        [playVideoButton addSubview:playVideoCircleView];

        UIImageView *playVideoIconView = [UIImageView withTemplateImageName:@"play-solid-32"
                                                                  tintColor:UIColor.ows_blackColor];
        playVideoIconView.userInteractionEnabled = NO;
        [playVideoButton addSubview:playVideoIconView];

        CGFloat playVideoButtonWidth = ScaleFromIPhone5(70);
        CGFloat playVideoIconWidth = ScaleFromIPhone5(30);
        [playVideoButton autoSetDimensionsToSize:CGSizeMake(playVideoButtonWidth, playVideoButtonWidth)];
        [playVideoIconView autoSetDimensionsToSize:CGSizeMake(playVideoIconWidth, playVideoIconWidth)];
        [playVideoCircleView autoPinEdgesToSuperviewEdges];
        [playVideoIconView autoCenterInSuperview];
        [playVideoButton autoCenterInSuperview];
    }
}

- (UIView *)buildLoopingVideoPlayerView
{
    NSURL *_Nullable attachmentUrl = self.attachmentStream.originalMediaURL;
    if (!attachmentUrl) {
        OWSFailDebug(@"Invalid URL");
        return [[UIView alloc] init];
    }

    LoopingVideo *_Nullable video = [[LoopingVideo alloc] initWithUrl:attachmentUrl];
    if (!video) {
        OWSFailDebug(@"Invalid looping video");
        return [[UIView alloc] init];
    }

    LoopingVideoView *view = [[LoopingVideoView alloc] init];
    view.video = video;
    view.delegate = self;

    return view;
}

- (UIView *)buildVideoPlayerView
{
    NSURL *_Nullable attachmentUrl = self.attachmentStream.originalMediaURL;

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:[attachmentUrl path]]) {
        OWSFailDebug(@"Missing video file");
    }

    OWSVideoPlayer *player = [[OWSVideoPlayer alloc] initWithUrl:attachmentUrl];
    [player seekToTime:kCMTimeZero];
    player.delegate = self;
    self.videoPlayer = player;

    VideoPlayerView *playerView = [VideoPlayerView new];
    playerView.player = player.avPlayer;
    playerView.delegate = self;

    return playerView;
}

- (void)setShouldHideToolbars:(BOOL)shouldHideToolbars
{
    self.videoProgressBar.hidden = shouldHideToolbars;
}

- (void)addGestureRecognizersToView:(UIView *)view
{
    UITapGestureRecognizer *doubleTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didDoubleTapImage:)];
    doubleTap.numberOfTapsRequired = 2;
    [view addGestureRecognizer:doubleTap];

    UITapGestureRecognizer *singleTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didSingleTapImage:)];
    [singleTap requireGestureRecognizerToFail:doubleTap];
    [view addGestureRecognizer:singleTap];
}

#pragma mark - Gesture Recognizers

- (void)didSingleTapImage:(UITapGestureRecognizer *)gesture
{
    [self.delegate mediaDetailViewControllerDidTapMedia:self];
}

- (void)didDoubleTapImage:(UITapGestureRecognizer *)gesture
{
    OWSLogVerbose(@"did double tap image.");
    if (self.scrollView.zoomScale == self.scrollView.minimumZoomScale) {
        CGFloat kDoubleTapZoomScale = 2;

        CGFloat zoomWidth = self.scrollView.width / kDoubleTapZoomScale;
        CGFloat zoomHeight = self.scrollView.height / kDoubleTapZoomScale;

        // center zoom rect around tapLocation
        CGPoint tapLocation = [gesture locationInView:self.scrollView];
        CGFloat zoomX = MAX(0, tapLocation.x - zoomWidth / 2);
        CGFloat zoomY = MAX(0, tapLocation.y - zoomHeight / 2);

        CGRect zoomRect = CGRectMake(zoomX, zoomY, zoomWidth, zoomHeight);

        CGRect translatedRect = [self.mediaView convertRect:zoomRect fromView:self.scrollView];

        [self.scrollView zoomToRect:translatedRect animated:YES];
    } else {
        // If already zoomed in at all, zoom out all the way.
        [self zoomOutAnimated:YES];
    }
}

- (void)didPressPlayBarButton:(id)sender
{
    OWSAssertDebug(self.isVideo);
    OWSAssertDebug(self.videoPlayer);
    [self playVideo];
}

- (void)didPressPauseBarButton:(id)sender
{
    OWSAssertDebug(self.isVideo);
    OWSAssertDebug(self.videoPlayer);
    [self pauseVideo];
}

#pragma mark -

- (void)updateZoomScaleAndConstraints
{
    // We want a default layout that...
    //
    // * Has the media visually centered.
    // * The media content should be zoomed to just barely fit by default,
    //   regardless of the content size.
    // * We should be able to safely zoom.
    // * The "min zoom scale" should satisfy the requirements above.
    // * The user should be able to scale in 4x.
    //
    // We use constraint-based layout and adjust
    // UIScrollView.minimumZoomScale, etc.

    // Determine the media's aspect ratio.
    //
    // * mediaView.intrinsicContentSize is most accurate, but
    //   may not be available yet for media that is loaded async.
    // * The self.image.size should always be available if the
    //   media is valid.
    CGSize mediaSize = CGSizeZero;
    CGSize mediaIntrinsicSize = self.mediaView.intrinsicContentSize;
    CGSize mediaDefaultSize = self.image.size;
    if (mediaIntrinsicSize.width > 0 && mediaIntrinsicSize.height > 0) {
        mediaSize = mediaIntrinsicSize;
    } else if (mediaDefaultSize.width > 0 && mediaDefaultSize.height > 0) {
        mediaSize = mediaDefaultSize;
    }

    CGSize scrollViewSize = self.scrollView.bounds.size;

    if (mediaSize.width <= 0 ||
        mediaSize.height <= 0 ||
        scrollViewSize.width <= 0 ||
        scrollViewSize.height <= 0) {
        // Invalid content or view state.

        self.scrollView.minimumZoomScale = 1.f;
        self.scrollView.maximumZoomScale = 1.f;
        self.scrollView.zoomScale = 1.f;

        self.mediaViewTopConstraint.constant = 0;
        self.mediaViewBottomConstraint.constant = 0;
        self.mediaViewLeadingConstraint.constant = 0;
        self.mediaViewTrailingConstraint.constant = 0;

        return;
    }

    // Center the media view in the scroll view.
    CGSize mediaViewSize = self.mediaView.frame.size;
    CGFloat yOffset = MAX(0, (scrollViewSize.height - mediaViewSize.height) / 2);
    CGFloat xOffset = MAX(0, (scrollViewSize.width - mediaViewSize.width) / 2);
    self.mediaViewTopConstraint.constant = yOffset;
    self.mediaViewBottomConstraint.constant = yOffset;
    self.mediaViewLeadingConstraint.constant = xOffset;
    self.mediaViewTrailingConstraint.constant = xOffset;

    // Find minScale for .scaleAspectFit-style layout.
    CGFloat scaleWidth = scrollViewSize.width / mediaSize.width;
    CGFloat scaleHeight = scrollViewSize.height / mediaSize.height;
    CGFloat minScale = MIN(scaleWidth, scaleHeight);
    CGFloat maxScale = minScale * 8;

    self.scrollView.minimumZoomScale = minScale;
    self.scrollView.maximumZoomScale = maxScale;

    if (self.scrollView.zoomScale < minScale) {
        self.scrollView.zoomScale = minScale;
    } else if (self.scrollView.zoomScale > maxScale) {
        self.scrollView.zoomScale = maxScale;
    }
}

#pragma mark - UIScrollViewDelegate

- (nullable UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    return self.mediaView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView
{
    [self updateZoomScaleAndConstraints];
    [self.view layoutIfNeeded];
}

- (void)resetMediaFrame
{
    // HACK: Setting the frame to itself *seems* like it should be a no-op, but
    // it ensures the content is drawn at the right frame. In particular I was
    // reproducibly seeing some images squished (they were EXIF rotated, maybe
    // related). similar to this report:
    // https://stackoverflow.com/questions/27961884/swift-uiimageview-stretched-aspect
    [self.view layoutIfNeeded];
    self.mediaView.frame = self.mediaView.frame;
}

#pragma mark - Video Playback

- (void)playVideo
{
    OWSAssertDebug(self.videoPlayer);

    self.playVideoButton.hidden = YES;

    [self.videoPlayer play];

    [self.delegate mediaDetailViewController:self isPlayingVideo:YES];
}

- (void)pauseVideo
{
    OWSAssertDebug(self.isVideo);
    OWSAssertDebug(self.videoPlayer);

    [self.videoPlayer pause];

    [self.delegate mediaDetailViewController:self isPlayingVideo:NO];
}

- (void)stopAnyVideo
{
    if (self.isVideo) {
        [self stopVideo];
    }
}

- (void)stopVideo
{
    OWSAssertDebug(self.isVideo);
    OWSAssertDebug(self.videoPlayer);

    [self.videoPlayer stop];

    self.playVideoButton.hidden = NO;

    [self.delegate mediaDetailViewController:self isPlayingVideo:NO];
}

#pragma mark - OWSVideoPlayer

- (void)videoPlayerDidPlayToCompletion:(OWSVideoPlayer *)videoPlayer
{
    OWSAssertDebug(self.isVideo);
    OWSAssertDebug(self.videoPlayer);
    OWSLogVerbose(@"");

    [self stopVideo];
}

#pragma mark - PlayerProgressBarDelegate

- (void)playerProgressBarDidStartScrubbing:(PlayerProgressBar *)playerProgressBar
{
    OWSAssertDebug(self.videoPlayer);
    [self.videoPlayer pause];
}

- (void)playerProgressBar:(PlayerProgressBar *)playerProgressBar scrubbedToTime:(CMTime)time
{
    OWSAssertDebug(self.videoPlayer);
    [self.videoPlayer seekToTime:time];
}

- (void)playerProgressBar:(PlayerProgressBar *)playerProgressBar
    didFinishScrubbingAtTime:(CMTime)time
        shouldResumePlayback:(BOOL)shouldResumePlayback
{
    OWSAssertDebug(self.videoPlayer);
    [self.videoPlayer seekToTime:time];

    if (shouldResumePlayback) {
        [self.videoPlayer play];
    }
}

#pragma mark - Saving images to Camera Roll

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    if (error) {
        OWSLogWarn(@"There was a problem saving <%@> to camera roll.", error.userErrorDescription);
    }
}

#pragma mark - LoopingVideoViewDelegate

- (void)loopingVideoViewChangedPlayerItem {
    OWSAssertIsOnMainThread();
    
    [self updateZoomScaleAndConstraints];
    self.scrollView.zoomScale = self.scrollView.minimumZoomScale;
}

#pragma mark - VideoPlayerViewDelegate

- (void)videoPlayerViewStatusDidChange:(VideoPlayerView *)view
{
    OWSAssertIsOnMainThread();

    [self updateZoomScaleAndConstraints];
}

- (void)videoPlayerViewPlaybackTimeDidChange:(VideoPlayerView *)view
{
    OWSAssertIsOnMainThread();

    // Do nothing.
}

@end

NS_ASSUME_NONNULL_END
