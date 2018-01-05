//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "FullImageViewController.h"
#import "AttachmentSharing.h"
#import "ConversationViewItem.h"
#import "Signal-Swift.h"
#import "TSAttachmentStream.h"
#import "TSInteraction.h"
#import "UIColor+OWS.h"
#import "UIUtil.h"
#import "UIView+OWS.h"
#import <AVKit/AVKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <SignalServiceKit/NSData+Image.h>
#import <YYImage/YYImage.h>

NS_ASSUME_NONNULL_BEGIN

#define kMinZoomScale 1.0f
#define kMaxZoomScale 8.0f

// In order to use UIMenuController, the view from which it is
// presented must have certain custom behaviors.
@interface AttachmentMenuView : UIView

@end

#pragma mark -

@implementation AttachmentMenuView

- (BOOL)canBecomeFirstResponder {
    return YES;
}

// We only use custom actions in UIMenuController.
- (BOOL)canPerformAction:(SEL)action withSender:(nullable id)sender
{
    return NO;
}

@end

#pragma mark -

@interface FullImageViewController () <UIScrollViewDelegate, UIGestureRecognizerDelegate>

@property (nonatomic) UIScrollView *scrollView;
@property (nonatomic) UIImageView *imageView;

@property (nonatomic) UIButton *shareButton;

@property (nonatomic) CGRect originRect;
@property (nonatomic) NSData *fileData;

@property (nonatomic, nullable) TSAttachmentStream *attachmentStream;
@property (nonatomic, nullable) SignalAttachment *attachment;
@property (nonatomic, nullable) ConversationViewItem *viewItem;

@property (nonatomic) UIToolbar *footerBar;
@property (nonatomic) BOOL areToolbarsHidden;
@property (nonatomic, nullable) MPMoviePlayerController *mpVideoPlayer;
@property (nonatomic, nullable) AVPlayer *videoPlayer;

@property (nonatomic, nullable) NSArray<NSLayoutConstraint *> *imageViewConstraints;
@property (nonatomic, nullable) NSLayoutConstraint *imageViewBottomConstraint;
@property (nonatomic, nullable) NSLayoutConstraint *imageViewLeadingConstraint;
@property (nonatomic, nullable) NSLayoutConstraint *imageViewTopConstraint;
@property (nonatomic, nullable) NSLayoutConstraint *imageViewTrailingConstraint;

@end

@implementation FullImageViewController

- (instancetype)initWithAttachmentStream:(TSAttachmentStream *)attachmentStream
                                fromRect:(CGRect)rect
                                viewItem:(ConversationViewItem *_Nullable)viewItem
{
    self = [super initWithNibName:nil bundle:nil];

    if (self) {
        self.attachmentStream = attachmentStream;
        self.originRect  = rect;
        self.viewItem = viewItem;
    }

    return self;
}

- (instancetype)initWithAttachment:(SignalAttachment *)attachment fromRect:(CGRect)rect
{
    self = [super initWithNibName:nil bundle:nil];

    if (self) {
        self.attachment = attachment;
        self.originRect = rect;
    }

    return self;
}

- (NSURL *_Nullable)attachmentUrl
{
    if (self.attachmentStream) {
        return self.attachmentStream.mediaURL;
    } else if (self.attachment) {
        return self.attachment.dataUrl;
    } else {
        return nil;
    }
}

- (NSData *)fileData
{
    if (!_fileData) {
        NSURL *_Nullable url = self.attachmentUrl;
        if (url) {
            _fileData = [NSData dataWithContentsOfURL:url];
        }
    }
    return _fileData;
}

- (UIImage *)image {
    if (self.attachmentStream) {
        return self.attachmentStream.image;
    } else if (self.attachment) {
        return self.attachment.image;
    } else {
        return nil;
    }
}

- (BOOL)isAnimated
{
    if (self.attachmentStream) {
        return self.attachmentStream.isAnimated;
    } else if (self.attachment) {
        return self.attachment.isAnimatedImage;
    } else {
        return NO;
    }
}

- (BOOL)isVideo
{
    if (self.attachmentStream) {
        return self.attachmentStream.isVideo;
    } else if (self.attachment) {
        return self.attachment.isVideo;
    } else {
        return NO;
    }
}

- (void)loadView
{
    self.view = [AttachmentMenuView new];
    self.view.backgroundColor = [UIColor clearColor];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self createContents];
    [self initializeGestureRecognizers];

    // Even though bars are opaque, we want content to be layed out behind them.
    // The bars might obscure part of the content, but they can easily be hidden by tapping
    // The alternative would be that content would shift when the navbars hide.
    self.extendedLayoutIncludesOpaqueBars = YES;

    // TODO better title.
    self.title = @"Attachment";

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                      target:self
                                                      action:@selector(didTapDismissButton:)];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    if ([UIMenuController sharedMenuController].isMenuVisible) {
        [[UIMenuController sharedMenuController] setMenuVisible:NO
                                                       animated:NO];
    }
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self updateMinZoomScale];
    [self centerImageViewConstraints];
}

- (void)updateMinZoomScale
{
    CGSize viewSize = self.scrollView.bounds.size;
    UIImage *image = self.imageView.image;
    OWSAssert(image);

    if (image.size.width == 0 || image.size.height == 0) {
        OWSFail(@"%@ Invalid image dimensions. %@", self.logTag, NSStringFromCGSize(image.size));
        return;
    }

    CGFloat scaleWidth = viewSize.width / image.size.width;
    CGFloat scaleHeight = viewSize.height / image.size.height;
    CGFloat minScale = MIN(scaleWidth, scaleHeight);
    self.scrollView.minimumZoomScale = minScale;
    self.scrollView.zoomScale = minScale;
}

#pragma mark - Initializers

- (void)createContents
{
    CGFloat kFooterHeight = 44;

    UIScrollView *scrollView = [UIScrollView new];
    [self.view addSubview:scrollView];
    self.scrollView = scrollView;
    scrollView.delegate = self;

    // TODO set max based on MIN.
    scrollView.maximumZoomScale = kMaxZoomScale;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.decelerationRate = UIScrollViewDecelerationRateFast;
    self.automaticallyAdjustsScrollViewInsets = NO;

    [scrollView autoPinToSuperviewEdges];

    if (self.isAnimated) {
        if ([self.fileData ows_isValidImage]) {
            YYImage *animatedGif = [YYImage imageWithData:self.fileData];
            YYAnimatedImageView *animatedView = [[YYAnimatedImageView alloc] init];
            animatedView.image = animatedGif;
            self.imageView = animatedView;
        } else {
            self.imageView = [UIImageView new];
        }
    } else if (self.isVideo) {
        [self setupVideoPlayer];

        // Present the static video preview
        UIImageView *imageView = [[UIImageView alloc] initWithImage:self.image];
        self.imageView = imageView;

    } else {
        // Present the static image using standard UIImageView
        UIImageView *imageView = [[UIImageView alloc] initWithImage:self.image];

        self.imageView = imageView;
    }

    OWSAssert(self.imageView);

    [scrollView addSubview:self.imageView];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.userInteractionEnabled = YES;
    self.imageView.clipsToBounds = YES;
    self.imageView.layer.allowsEdgeAntialiasing = YES;
    self.imageView.translatesAutoresizingMaskIntoConstraints = NO;

    // Use trilinear filters for better scaling quality at
    // some performance cost.
    self.imageView.layer.minificationFilter = kCAFilterTrilinear;
    self.imageView.layer.magnificationFilter = kCAFilterTrilinear;

    [self applyInitialImageViewConstraints];

    if (self.isVideo) {
        UIButton *playButton = [UIButton new];

        [playButton addTarget:self action:@selector(playVideo) forControlEvents:UIControlEventTouchUpInside];

        UIImage *playImage = [UIImage imageNamed:@"play_button"];
        [playButton setBackgroundImage:playImage forState:UIControlStateNormal];
        playButton.contentMode = UIViewContentModeScaleAspectFill;

        [self.view addSubview:playButton];

        CGFloat playButtonWidth = ScaleFromIPhone5(70);
        [playButton autoSetDimensionsToSize:CGSizeMake(playButtonWidth, playButtonWidth)];
        [playButton autoCenterInSuperview];
    }

    UIToolbar *footerBar = [UIToolbar new];
    _footerBar = footerBar;
    footerBar.barTintColor = [UIColor ows_signalBrandBlueColor];
    [footerBar setItems:@[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                      target:self
                                                      action:@selector(didPressShare:)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
                                                      target:self
                                                      action:@selector(didPressDelete:)],
    ]
               animated:NO];
    [self.view addSubview:footerBar];

    [footerBar autoPinWidthToSuperview];
    [footerBar autoPinToBottomLayoutGuideOfViewController:self withInset:0];
    [footerBar autoSetDimension:ALDimensionHeight toSize:kFooterHeight];
}

- (void)applyInitialImageViewConstraints
{
    if (self.imageViewConstraints.count > 0) {
        [NSLayoutConstraint deactivateConstraints:self.imageViewConstraints];
    }

    CGRect convertedRect =
        [self.imageView.superview convertRect:self.originRect fromView:[UIApplication sharedApplication].keyWindow];

    NSMutableArray<NSLayoutConstraint *> *imageViewConstraints = [NSMutableArray new];
    self.imageViewConstraints = imageViewConstraints;

    [imageViewConstraints addObjectsFromArray:[self.imageView autoSetDimensionsToSize:convertedRect.size]];
    [imageViewConstraints addObjectsFromArray:@[
        [self.imageView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:convertedRect.origin.y],
        [self.imageView autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:convertedRect.origin.x]
    ]];
}

- (void)applyFinalImageViewConstraints
{
    if (self.imageViewConstraints.count > 0) {
        [NSLayoutConstraint deactivateConstraints:self.imageViewConstraints];
    }

    NSMutableArray<NSLayoutConstraint *> *imageViewConstraints = [NSMutableArray new];
    self.imageViewConstraints = imageViewConstraints;

    self.imageViewLeadingConstraint = [self.imageView autoPinEdgeToSuperviewEdge:ALEdgeLeading];
    self.imageViewTopConstraint = [self.imageView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    self.imageViewTrailingConstraint = [self.imageView autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    self.imageViewBottomConstraint = [self.imageView autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    [imageViewConstraints addObjectsFromArray:@[
        self.imageViewTopConstraint,
        self.imageViewTrailingConstraint,
        self.imageViewBottomConstraint,
        self.imageViewLeadingConstraint
    ]];
}

- (void)setupVideoPlayer
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:[self.attachmentUrl path]]) {
        OWSFail(@"%@ Missing video file: %@", self.logTag, self.attachmentStream.mediaURL);
    }

    if (@available(iOS 9.0, *)) {
        AVPlayer *player = [[AVPlayer alloc] initWithURL:self.attachmentUrl];
        self.videoPlayer = player;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(playerItemDidPlayToCompletion:)
                                                     name:AVPlayerItemDidPlayToEndTimeNotification
                                                   object:player.currentItem];
    } else {
        MPMoviePlayerController *videoPlayer =
            [[MPMoviePlayerController alloc] initWithContentURL:self.attachmentStream.mediaURL];
        self.mpVideoPlayer = videoPlayer;

        videoPlayer.controlStyle = MPMovieControlStyleNone;
        [videoPlayer prepareToPlay];

        //
        //        [[NSNotificationCenter defaultCenter] addObserver:self
        //                                                 selector:@selector(moviePlayerWillExitFullscreen:)
        //                                                     name:MPMoviePlayerWillExitFullscreenNotification
        //                                                   object:videoPlayer];
        //        [[NSNotificationCenter defaultCenter] addObserver:self
        //                                                 selector:@selector(moviePlayerDidExitFullscreen:)
        //                                                     name:MPMoviePlayerDidExitFullscreenNotification
        //                                                   object:videoPlayer];
        //        [[NSNotificationCenter defaultCenter] addObserver:self
        //                                                 selector:@selector(moviePlayerWillEnterFullscreen:)
        //                                                     name:MPMoviePlayerWillEnterFullscreenNotification
        //                                                   object:videoPlayer];
        //        [[NSNotificationCenter defaultCenter] addObserver:self
        //                                                 selector:@selector(moviePlayerPlaybackStateDidChange:)
        //                                                     name:MPMoviePlayerPlaybackStateDidChangeNotification
        //                                                   object:videoPlayer];
        //
        //        [[NSNotificationCenter defaultCenter] addObserver:self
        //                                                 selector:@selector(moviePlayerDidEnterFullscreen:)
        //                                                     name:MPMoviePlayerDidEnterFullscreenNotification
        //                                                   object:videoPlayer];
        //
        //
        //        [[NSNotificationCenter defaultCenter] addObserver:self
        //                                                 selector:@selector(moviePlayerDidFinishPlayback:)
        //                                                     name:MPMoviePlayerPlaybackDidFinishNotification
        //                                                   object:videoPlayer];
        //
        //        // Don't show any controls intially. We switch control style after the view is fullscreen to make them
        //        appear upon tapping.
        ////        videoPlayer.controlStyle = MPMovieControlStyleFullscreen;
        //        videoPlayer.shouldAutoplay = YES;
        //
        //        // We can't animate from the cell media frame;
        //        // MPMoviePlayerController will animate a crop of its
        //        // contents rather than scaling them.
        //        videoPlayer.view.frame = self.view.bounds;
        //
        //        self.imageView = videoPlayer.view;
    }
}

- (void)setAreToolbarsHidden:(BOOL)areToolbarsHidden
{
    if (_areToolbarsHidden == areToolbarsHidden) {
        return;
    }

    _areToolbarsHidden = areToolbarsHidden;

    if (!areToolbarsHidden) {
        // Hiding the status bar affects the positioing of the navbar. We don't want to show that in the animation
        // so when *showing* the toolbars, we show the status bar first. When hiding, we hide it last.
        [[UIApplication sharedApplication] setStatusBarHidden:areToolbarsHidden withAnimation:UIStatusBarAnimationFade];
    }
    [UIView animateWithDuration:0.1
        animations:^(void) {
            self.view.backgroundColor = areToolbarsHidden ? UIColor.blackColor : UIColor.whiteColor;
            self.navigationController.navigationBar.alpha = areToolbarsHidden ? 0 : 1;
            self.footerBar.alpha = areToolbarsHidden ? 0 : 1;
        }
        completion:^(BOOL finished) {
            // although navbar has 0 alpha at this point, if we don't also "hide" it, adjusting the status bar
            // resets the alpha.
            if (areToolbarsHidden) {
                //                             [self.navigationController setNavigationBarHidden:areToolbarsHidden
                //                             animated:NO];
                // Hiding the status bar affects the positioing of the navbar. We don't want to show that in the
                // animation so when *showing* the toolbars, we show the status bar first. When hiding, we hide it last.
                [[UIApplication sharedApplication] setStatusBarHidden:areToolbarsHidden
                                                        withAnimation:UIStatusBarAnimationNone];
                // position the navbar, but have it be transparent
                self.navigationController.navigationBar.alpha = 0;
            }
        }];
}

- (void)initializeGestureRecognizers
{
    UITapGestureRecognizer *doubleTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didDoubleTapImage:)];
    doubleTap.numberOfTapsRequired = 2;
    [self.view addGestureRecognizer:doubleTap];

    UITapGestureRecognizer *singleTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didTapImage:)];
    [singleTap requireGestureRecognizerToFail:doubleTap];

    [self.view addGestureRecognizer:singleTap];

    // UISwipeGestureRecognizer supposedly supports multiple directions,
    // but in practice it works better if you use a separate GR for each
    // direction.
    for (NSNumber *direction in @[
                                  @(UISwipeGestureRecognizerDirectionRight),
                                  @(UISwipeGestureRecognizerDirectionLeft),
                                  @(UISwipeGestureRecognizerDirectionUp),
                                  @(UISwipeGestureRecognizerDirectionDown),
                                  ]) {
        UISwipeGestureRecognizer *swipe =
            [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(didSwipeImage:)];
        swipe.direction = (UISwipeGestureRecognizerDirection) direction.integerValue;
        swipe.delegate = self;
        [self.view addGestureRecognizer:swipe];
    }

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                            action:@selector(longPressGesture:)];
    longPress.delegate = self;
    [self.view addGestureRecognizer:longPress];
}

#pragma mark - Gesture Recognizers


- (void)didTapDismissButton:(id)sender
{
    [self dismiss];
}

- (void)didTapImage:(id)sender
{
    DDLogVerbose(@"%@ did tap image.", self.logTag);
    self.areToolbarsHidden = !self.areToolbarsHidden;
}

- (void)didDoubleTapImage:(id)sender
{
    DDLogVerbose(@"%@ did tap image.", self.logTag);
    if (self.scrollView.zoomScale == self.scrollView.minimumZoomScale) {
        [self.scrollView setZoomScale:self.scrollView.minimumZoomScale * 2 animated:YES];
    } else {
        [self.scrollView setZoomScale:self.scrollView.minimumZoomScale animated:YES];
    }
}

- (void)didSwipeImage:(UIGestureRecognizer *)sender
{
    // Ignore if image is zoomed in at all.
    // e.g. otherwise, for example, if the image is horizontally larger than the scroll
    // view, but fits vertically, swiping left/right will scroll the image, but swiping up/down
    // would dismiss the image. That would not be intuitive.
    if (self.scrollView.zoomScale != self.scrollView.minimumZoomScale) {
        return;
    }

    [self dismiss];
}

- (void)longPressGesture:(UIGestureRecognizer *)sender {
    // We "eagerly" respond when the long press begins, not when it ends.
    if (sender.state == UIGestureRecognizerStateBegan) {
        if (!self.viewItem) {
            return;
        }

        [self.view becomeFirstResponder];
        
        if ([UIMenuController sharedMenuController].isMenuVisible) {
            [[UIMenuController sharedMenuController] setMenuVisible:NO
                                                           animated:NO];
        }

        NSArray *menuItems = self.viewItem.menuControllerItems;
        [UIMenuController sharedMenuController].menuItems = menuItems;
        CGPoint location = [sender locationInView:self.view];
        CGRect targetRect = CGRectMake(location.x,
                                       location.y,
                                       1, 1);
        [[UIMenuController sharedMenuController] setTargetRect:targetRect
                                                        inView:self.view];
        [[UIMenuController sharedMenuController] setMenuVisible:YES
                                                       animated:YES];
    }
}

- (void)didPressShare:(id)sender
{
    DDLogInfo(@"%@: sharing image.", self.logTag);

    [self.viewItem shareAction];
}

- (void)didPressDelete:(id)sender
{
    DDLogInfo(@"%@: sharing image.", self.logTag);

    UIAlertController *actionSheet =
        [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [actionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_DELETE_TITLE", nil)
                                                    style:UIAlertActionStyleDestructive
                                                  handler:^(UIAlertAction *action) {
                                                      [self.viewItem deleteAction];
                                                      [self dismiss];
                                                  }]];

    [actionSheet addAction:[OWSAlerts cancelAction]];

    [self presentViewController:actionSheet animated:YES completion:nil];
}

- (BOOL)canPerformAction:(SEL)action withSender:(nullable id)sender
{
    if (action == self.viewItem.metadataActionSelector) {
        return NO;
    }
    return [self.viewItem canPerformAction:action];
}

- (void)copyAction:(nullable id)sender
{
    [self.viewItem copyAction];
}

- (void)shareAction:(nullable id)sender
{
    [self.viewItem shareAction];
}

- (void)saveAction:(nullable id)sender
{
    [self.viewItem saveAction];
}

- (void)deleteAction:(nullable id)sender
{
    [self didPressDelete:sender];
}

#pragma mark - Presentation

- (void)presentFromViewController:(UIViewController *)viewController
{
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:self];

    // UIModalPresentationCustom retains the current view context behind our VC, allowing us to manually
    // animate in our view, over the existing context, similar to a cross disolve, but allowing us to have
    // more fine grained control
    navController.modalPresentationStyle = UIModalPresentationCustom;
    navController.navigationBar.barTintColor = UIColor.ows_materialBlueColor;
    navController.navigationBar.translucent = NO;
    navController.navigationBar.opaque = YES;

    self.view.userInteractionEnabled = NO;

    self.view.alpha = 0.0;
    [viewController presentViewController:navController
                                 animated:NO
                               completion:^{

                                   // 1. Fade in the entire view.
                                   [UIView animateWithDuration:0.1
                                                    animations:^{
                                                        self.view.alpha = 1.0;
                                                    }];

                                   // Make sure imageView is layed out before we update it's frame in the next
                                   // animation.
                                   [self.imageView.superview layoutIfNeeded];

                                   // 2. Animate imageView from it's initial position, which should match where it was
                                   // in the presenting view to it's final position, front and center in this view. This
                                   // animation intentionally overlaps the previous
                                   [UIView animateWithDuration:0.2
                                       delay:0.08
                                       options:UIViewAnimationOptionCurveEaseOut
                                       animations:^(void) {
                                           [self applyFinalImageViewConstraints];
                                           [self.imageView.superview layoutIfNeeded];
                                           // We must lay out *before* we centerImageViewConstraints
                                           // because it uses the imageView.frame to build the contstraints
                                           // that will center the imageView, and then once again
                                           // to ensure that the centered constraints are applied.
                                           [self centerImageViewConstraints];
                                           [self.imageView.superview layoutIfNeeded];
                                           self.view.backgroundColor = UIColor.whiteColor;
                                       }
                                       completion:^(BOOL finished) {
                                           self.view.userInteractionEnabled = YES;

                                           if (self.isVideo) {
                                               [self playVideo];
                                           }
                                       }];
                               }];
}

- (void)dismiss
{
    self.view.userInteractionEnabled = NO;
    [UIApplication sharedApplication].statusBarHidden = NO;

    OWSAssert(self.imageView.superview);

    [self.imageView.superview layoutIfNeeded];

    // Move the image view pack to it's initial position, i.e. where
    // it sits on the screen in the conversation view.
    [self applyInitialImageViewConstraints];
    [UIView animateWithDuration:0.2
        delay:0.0
        options:UIViewAnimationOptionCurveEaseInOut
        animations:^(void) {
            [self.imageView.superview layoutIfNeeded];

            // In case user has hidden bars, which changes background to black.
            self.view.backgroundColor = UIColor.whiteColor;

            // fade out content and toolbars
            self.navigationController.view.alpha = 0.0;
        }
        completion:^(BOOL finished) {
            [self.presentingViewController dismissViewControllerAnimated:NO completion:nil];
        }];
}

#pragma mark - UIScrollViewDelegate

- (nullable UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    return self.imageView;
}

- (void)centerImageViewConstraints
{
    OWSAssert(self.scrollView);

    CGSize scrollViewSize = self.scrollView.bounds.size;
    CGSize imageViewSize = self.imageView.frame.size;

    CGFloat yOffset = MAX(0, (scrollViewSize.height - imageViewSize.height) / 2);
    self.imageViewTopConstraint.constant = yOffset;
    self.imageViewBottomConstraint.constant = yOffset;

    CGFloat xOffset = MAX(0, (scrollViewSize.width - imageViewSize.width) / 2);
    self.imageViewLeadingConstraint.constant = xOffset;
    self.imageViewTrailingConstraint.constant = xOffset;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView
{
    [self centerImageViewConstraints];
    [self.view layoutIfNeeded];
}

#pragma mark - Video Playback

- (void)playVideo
{
    OWSAssert(self.isVideo);
    OWSAssert(self.videoPlayer);

    AVPlayerViewController *vc = [AVPlayerViewController new];
    AVPlayer *player = self.videoPlayer;
    vc.player = player;

    vc.modalPresentationStyle = UIModalPresentationCustom;
    vc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;

    // Rewind for repeated plays
    [player seekToTime:kCMTimeZero];
    [self presentViewController:vc
                       animated:NO
                     completion:^(void) {
                         [player play];
                     }];
}

- (void)playerItemDidPlayToCompletion:(NSNotification *)notification
{
    OWSAssert(self.isVideo);
    OWSAssert(self.videoPlayer);
    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    [self dismissViewControllerAnimated:NO completion:nil];
}

- (void)moviePlayerPlaybackStateDidChange:(NSNotification *)notification
{
    DDLogDebug(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);
    OWSAssert(self.mpVideoPlayer);
}

- (void)moviePlayerWillEnterFullscreen:(NSNotification *)notification
{
    DDLogDebug(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);
    OWSAssert(self.videoPlayer);
    self.mpVideoPlayer.controlStyle = MPMovieControlStyleNone;
}

- (void)moviePlayerDidEnterFullscreen:(NSNotification *)notification
{
    DDLogDebug(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);
    OWSAssert(self.videoPlayer);
    self.mpVideoPlayer.controlStyle = MPMovieControlStyleFullscreen;
}

// There's more than one way to exit the fullscreen video playback.
// There's a done button, a "toggle fullscreen" button and I think
// there's some gestures too.  These fire slightly different notifications.
// We want to hide & clean up the video player immediately in all of
// these cases.
- (void)moviePlayerWillExitFullscreen:(NSNotification *)notification
{
    DDLogDebug(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    // If we didn't just complete playback, user chose to exit fullscreen.
    // In that case, we dismiss the view controller since the user is probably done.
    //    if (!self.didJustCompleteVideoPlayback) {
    //        [self dismiss];
    //    }

    //    self.didJustCompleteVideoPlayback = NO;
    self.mpVideoPlayer.controlStyle = MPMovieControlStyleNone;

    //    [self clearVideoPlayer];
}

// See comment on moviePlayerWillExitFullscreen:
- (void)moviePlayerDidExitFullscreen:(NSNotification *)notification
{
    DDLogDebug(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);
    self.mpVideoPlayer.controlStyle = MPMovieControlStyleEmbedded;
    //    [self clearVideoPlayer];
}

- (void)moviePlayerDidFinishPlayback:(NSNotification *)notification
{
    OWSAssert(self.videoPlayer);

    NSNumber *reason = notification.userInfo[MPMoviePlayerPlaybackDidFinishReasonUserInfoKey];
    DDLogDebug(@"%@ movie player finished with reason %@", self.logTag, reason);
    OWSAssert(reason);

    switch (reason.integerValue) {
        case MPMovieFinishReasonPlaybackEnded: {
            DDLogDebug(@"%@ video played to completion.", self.logTag);
            self.mpVideoPlayer.controlStyle = MPMovieControlStyleNone;
            [self.mpVideoPlayer setFullscreen:NO animated:YES];
            break;
        }
        case MPMovieFinishReasonPlaybackError: {
            DDLogDebug(@"%@ error playing video.", self.logTag);
            break;
        }
        case MPMovieFinishReasonUserExited: {
            // FIXME: unable to fire this (only tried on iOS11.2 so far)
            DDLogDebug(@"%@ user exited video playback", self.logTag);
            [self dismiss];
            break;
        }
    }
}

//- (void)clearVideoPlayer
//{
//    [self.videoPlayer stop];
//    [self.videoPlayer.view removeFromSuperview];
//    self.videoPlayer = nil;
//}

//- (void)setVideoPlayer:(MPMoviePlayerController *_Nullable)videoPlayer
//{
//    _mpVideoPlayer = mpVideoPlayer;
//
//    [ViewControllerUtils setAudioIgnoresHardwareMuteSwitch:videoPlayer != nil];
//}

#pragma mark - Saving images to Camera Roll

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    if (error) {
        DDLogWarn(@"There was a problem saving <%@> to camera roll from %s ",
                  error.localizedDescription,
                  __PRETTY_FUNCTION__);
    }
}

@end

NS_ASSUME_NONNULL_END
