//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "MediaDetailViewController.h"
#import "AttachmentSharing.h"
#import "ConversationViewController.h"
#import "ConversationViewItem.h"
#import "OWSMessageCell.h"
#import "Signal-Swift.h"
#import "TSAttachmentStream.h"
#import "TSInteraction.h"
#import "UIColor+OWS.h"
#import "UIUtil.h"
#import "UIView+OWS.h"
#import <AVKit/AVKit.h>
#import <MediaPlayer/MPMoviePlayerViewController.h>
#import <MediaPlayer/MediaPlayer.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/NSData+Image.h>
#import <YYImage/YYImage.h>

NS_ASSUME_NONNULL_BEGIN

// In order to use UIMenuController, the view from which it is
// presented must have certain custom behaviors.
@interface AttachmentMenuView : UIView

@end

#pragma mark -

@implementation AttachmentMenuView

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

// We only use custom actions in UIMenuController.
- (BOOL)canPerformAction:(SEL)action withSender:(nullable id)sender
{
    return NO;
}

@end

#pragma mark -

@interface MediaDetailViewController () <UIScrollViewDelegate,
    UIGestureRecognizerDelegate,
    PlayerProgressBarDelegate,
    OWSVideoPlayerDelegate>

@property (nonatomic) UIScrollView *scrollView;
@property (nonatomic) UIView *mediaView;
@property (nonatomic) UIView *presentationView;
@property (nonatomic) UIView *replacingView;
@property (nonatomic) UIButton *shareButton;

@property (nonatomic) CGRect originRect;
@property (nonatomic) NSData *fileData;

@property (nonatomic, nullable) TSAttachmentStream *attachmentStream;
@property (nonatomic, nullable) SignalAttachment *attachment;
@property (nonatomic, nullable) ConversationViewItem *viewItem;

@property (nonatomic) UIToolbar *footerBar;
@property (nonatomic) BOOL areToolbarsHidden;

@property (nonatomic, nullable) OWSVideoPlayer *videoPlayer;
@property (nonatomic, nullable) UIButton *playVideoButton;
@property (nonatomic, nullable) PlayerProgressBar *videoProgressBar;
@property (nonatomic, nullable) UIBarButtonItem *videoPlayBarButton;
@property (nonatomic, nullable) UIBarButtonItem *videoPauseBarButton;

@property (nonatomic, nullable) NSArray<NSLayoutConstraint *> *presentationViewConstraints;
@property (nonatomic, nullable) NSLayoutConstraint *mediaViewBottomConstraint;
@property (nonatomic, nullable) NSLayoutConstraint *mediaViewLeadingConstraint;
@property (nonatomic, nullable) NSLayoutConstraint *mediaViewTopConstraint;
@property (nonatomic, nullable) NSLayoutConstraint *mediaViewTrailingConstraint;

@end

@implementation MediaDetailViewController

- (instancetype)initWithAttachmentStream:(TSAttachmentStream *)attachmentStream
                                viewItem:(ConversationViewItem *_Nullable)viewItem
{
    self = [super initWithNibName:nil bundle:nil];
    if (!self) {
        return self;
    }

    self.attachmentStream = attachmentStream;
    self.viewItem = viewItem;

    return self;
}

- (instancetype)initWithAttachment:(SignalAttachment *)attachment
{
    self = [super initWithNibName:nil bundle:nil];
    if (!self) {
        return self;
    }

    self.attachment = attachment;

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

- (UIImage *)image
{
    if (self.attachmentStream) {
        return self.attachmentStream.image;
    } else if (self.attachment) {
        if (self.isVideo) {
            return self.attachment.videoPreview;
        } else {
            return self.attachment.image;
        }
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

    // FIXME better title.
    self.title = @"Attachment";

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                      target:self
                                                      action:@selector(didTapDismissButton:)];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];

    if ([UIMenuController sharedMenuController].isMenuVisible) {
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
    }
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    [self updateMinZoomScale];
    [self centerMediaViewConstraints];
}

- (void)updateMinZoomScale
{
    CGSize viewSize = self.scrollView.bounds.size;
    UIImage *image = self.image;
    OWSAssert(image);

    if (image.size.width == 0 || image.size.height == 0) {
        OWSFail(@"%@ Invalid image dimensions. %@", self.logTag, NSStringFromCGSize(image.size));
        return;
    }

    CGFloat scaleWidth = viewSize.width / image.size.width;
    CGFloat scaleHeight = viewSize.height / image.size.height;
    CGFloat minScale = MIN(scaleWidth, scaleHeight);

    if (minScale != self.scrollView.minimumZoomScale) {
        self.scrollView.minimumZoomScale = minScale;
        self.scrollView.maximumZoomScale = minScale * 8;
        self.scrollView.zoomScale = minScale;
    }
}

#pragma mark - Initializers

- (void)createContents
{
    CGFloat kFooterHeight = 44;

    UIScrollView *scrollView = [UIScrollView new];
    [self.view addSubview:scrollView];
    self.scrollView = scrollView;
    scrollView.delegate = self;

    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.decelerationRate = UIScrollViewDecelerationRateFast;

    if (@available(iOS 11.0, *)) {
        scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    } else {
        self.automaticallyAdjustsScrollViewInsets = NO;
    }

    [scrollView autoPinToSuperviewEdges];

    if (self.isAnimated) {
        if ([self.fileData ows_isValidImage]) {
            YYImage *animatedGif = [YYImage imageWithData:self.fileData];
            YYAnimatedImageView *animatedView = [YYAnimatedImageView new];
            animatedView.image = animatedGif;
            self.mediaView = animatedView;
        } else {
            self.mediaView = [UIImageView new];
        }
    } else if (self.isVideo) {
        self.mediaView = [self buildVideoPlayerView];
    } else {
        // Present the static image using standard UIImageView
        UIImageView *imageView = [[UIImageView alloc] initWithImage:self.image];

        self.mediaView = imageView;
    }

    OWSAssert(self.mediaView);

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

    // The presentationView is only used during present/dismiss animations.
    // It's a static image of the media content.
    UIImageView *presentationView = [[UIImageView alloc] initWithImage:self.image];
    self.presentationView = presentationView;

    [self.view addSubview:presentationView];
    presentationView.hidden = YES;
    presentationView.clipsToBounds = YES;
    presentationView.layer.allowsEdgeAntialiasing = YES;
    presentationView.layer.minificationFilter = kCAFilterTrilinear;
    presentationView.layer.magnificationFilter = kCAFilterTrilinear;
    presentationView.contentMode = UIViewContentModeScaleAspectFit;

    if (self.isVideo) {
        PlayerProgressBar *videoProgressBar = [PlayerProgressBar new];
        videoProgressBar.delegate = self;
        videoProgressBar.player = self.videoPlayer.avPlayer;

        self.videoProgressBar = videoProgressBar;
        [self.view addSubview:videoProgressBar];
        [videoProgressBar autoPinWidthToSuperview];
        [videoProgressBar autoPinToTopLayoutGuideOfViewController:self withInset:0];
        CGFloat kVideoProgressBarHeight = 44;
        [videoProgressBar autoSetDimension:ALDimensionHeight toSize:kVideoProgressBarHeight];

        UIButton *playVideoButton = [UIButton new];
        self.playVideoButton = playVideoButton;

        [playVideoButton addTarget:self action:@selector(playVideo) forControlEvents:UIControlEventTouchUpInside];

        UIImage *playImage = [UIImage imageNamed:@"play_button"];
        [playVideoButton setBackgroundImage:playImage forState:UIControlStateNormal];
        playVideoButton.contentMode = UIViewContentModeScaleAspectFill;

        [self.view addSubview:playVideoButton];

        CGFloat playVideoButtonWidth = ScaleFromIPhone5(70);
        [playVideoButton autoSetDimensionsToSize:CGSizeMake(playVideoButtonWidth, playVideoButtonWidth)];
        [playVideoButton autoCenterInSuperview];
    }

    // Don't show footer bar after tapping approval-view
    if (self.viewItem) {
        UIToolbar *footerBar = [UIToolbar new];
        _footerBar = footerBar;
        footerBar.barTintColor = [UIColor ows_signalBrandBlueColor];
        self.videoPlayBarButton =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPlay
                                                          target:self
                                                          action:@selector(didPressPlayBarButton:)];
        self.videoPauseBarButton =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPause
                                                          target:self
                                                          action:@selector(didPressPauseBarButton:)];
        [self updateFooterBarButtonItemsWithIsPlayingVideo:YES];
        [self.view addSubview:footerBar];

        [footerBar autoPinWidthToSuperview];
        [footerBar autoPinToBottomLayoutGuideOfViewController:self withInset:0];
        [footerBar autoSetDimension:ALDimensionHeight toSize:kFooterHeight];
    }
}

- (void)updateFooterBarButtonItemsWithIsPlayingVideo:(BOOL)isPlayingVideo
{
    if (!self.footerBar) {
        DDLogVerbose(@"%@ No footer bar visible.", self.logTag);
        return;
    }

    NSMutableArray<UIBarButtonItem *> *toolbarItems = [NSMutableArray new];

    [toolbarItems addObjectsFromArray:@[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                      target:self
                                                      action:@selector(didPressShare:)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
    ]];

    if (self.isVideo) {
        UIBarButtonItem *playerButton = isPlayingVideo ? self.videoPauseBarButton : self.videoPlayBarButton;
        [toolbarItems addObjectsFromArray:@[
            playerButton,
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                          target:nil
                                                          action:nil],
        ]];
    }

    [toolbarItems addObject:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
                                                                          target:self
                                                                          action:@selector(didPressDelete:)]];

    [self.footerBar setItems:toolbarItems animated:NO];
}

- (void)applyInitialMediaViewConstraints
{
    if (self.presentationViewConstraints.count > 0) {
        [NSLayoutConstraint deactivateConstraints:self.presentationViewConstraints];
    }

    OWSAssert(!CGRectEqualToRect(CGRectZero, self.originRect));
    CGRect convertedRect = [self.presentationView.superview convertRect:self.originRect
                                                               fromView:[UIApplication sharedApplication].keyWindow];

    NSMutableArray<NSLayoutConstraint *> *presentationViewConstraints = [NSMutableArray new];
    self.presentationViewConstraints = presentationViewConstraints;

    [presentationViewConstraints
        addObjectsFromArray:[self.presentationView autoSetDimensionsToSize:convertedRect.size]];
    [presentationViewConstraints addObjectsFromArray:@[
        [self.presentationView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:convertedRect.origin.y],
        [self.presentationView autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:convertedRect.origin.x]
    ]];
}

- (void)applyFinalMediaViewConstraints
{
    if (self.presentationViewConstraints.count > 0) {
        [NSLayoutConstraint deactivateConstraints:self.presentationViewConstraints];
    }

    NSMutableArray<NSLayoutConstraint *> *presentationViewConstraints = [NSMutableArray new];
    self.presentationViewConstraints = presentationViewConstraints;

    [presentationViewConstraints addObjectsFromArray:@[
        [self.presentationView autoPinEdgeToSuperviewEdge:ALEdgeLeading],
        [self.presentationView autoPinEdgeToSuperviewEdge:ALEdgeTop],
        [self.presentationView autoPinEdgeToSuperviewEdge:ALEdgeTrailing],
        [self.presentationView autoPinEdgeToSuperviewEdge:ALEdgeBottom]
    ]];
}

- (UIView *)buildVideoPlayerView
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:[self.attachmentUrl path]]) {
        OWSFail(@"%@ Missing video file: %@", self.logTag, self.attachmentStream.mediaURL);
    }

    OWSVideoPlayer *player = [[OWSVideoPlayer alloc] initWithUrl:self.attachmentUrl];
    [player seekToTime:kCMTimeZero];
    player.delegate = self;
    self.videoPlayer = player;

    VideoPlayerView *playerView = [VideoPlayerView new];
    playerView.player = player.avPlayer;

    [NSLayoutConstraint autoSetPriority:UILayoutPriorityDefaultLow
                         forConstraints:^{
                             [playerView autoSetDimensionsToSize:self.image.size];
                         }];

    return playerView;
}

- (void)setAreToolbarsHidden:(BOOL)areToolbarsHidden
{
    if (_areToolbarsHidden == areToolbarsHidden) {
        return;
    }

    _areToolbarsHidden = areToolbarsHidden;

    // Hiding the status bar affects the positioing of the navbar. We don't want to show that in an animation, it's
    // better to just have everythign "flit" in/out.
    [[UIApplication sharedApplication] setStatusBarHidden:areToolbarsHidden withAnimation:UIStatusBarAnimationNone];
    [self.navigationController setNavigationBarHidden:areToolbarsHidden animated:NO];
    self.videoProgressBar.hidden = areToolbarsHidden;

    // We don't animate the background color change because the old color shows through momentarily
    // behind where the status bar "used to be".
    self.view.backgroundColor = areToolbarsHidden ? UIColor.blackColor : UIColor.whiteColor;

    [UIView animateWithDuration:0.1
                     animations:^(void) {
                         self.footerBar.alpha = areToolbarsHidden ? 0 : 1;
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
        swipe.direction = (UISwipeGestureRecognizerDirection)direction.integerValue;
        swipe.delegate = self;
        [self.view addGestureRecognizer:swipe];
    }

    UILongPressGestureRecognizer *longPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressGesture:)];
    longPress.delegate = self;
    [self.view addGestureRecognizer:longPress];
}

#pragma mark - Gesture Recognizers

- (void)didTapDismissButton:(id)sender
{
    [self dismissSelfAnimated:YES completion:nil];
}

- (void)didTapImage:(id)sender
{
    DDLogVerbose(@"%@ did tap image.", self.logTag);
    self.areToolbarsHidden = !self.areToolbarsHidden;
}

- (void)didDoubleTapImage:(UITapGestureRecognizer *)gesture
{
    DDLogVerbose(@"%@ did double tap image.", self.logTag);
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

    [self dismissSelfAnimated:YES completion:nil];
}

- (void)longPressGesture:(UIGestureRecognizer *)sender
{
    // We "eagerly" respond when the long press begins, not when it ends.
    if (sender.state == UIGestureRecognizerStateBegan) {
        if (!self.viewItem) {
            return;
        }

        [self.view becomeFirstResponder];

        if ([UIMenuController sharedMenuController].isMenuVisible) {
            [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
        }

        NSArray *menuItems = self.viewItem.mediaMenuControllerItems;
        [UIMenuController sharedMenuController].menuItems = menuItems;
        CGPoint location = [sender locationInView:self.view];
        CGRect targetRect = CGRectMake(location.x, location.y, 1, 1);
        [[UIMenuController sharedMenuController] setTargetRect:targetRect inView:self.view];
        [[UIMenuController sharedMenuController] setMenuVisible:YES animated:YES];
    }
}

- (void)didPressShare:(id)sender
{
    DDLogInfo(@"%@: didPressShare", self.logTag);
    if (!self.viewItem) {
        OWSFail(@"share should only be available when a viewItem is present");
        return;
    }

    [self.viewItem shareMediaAction];
}

- (void)didPressDelete:(id)sender
{
    DDLogInfo(@"%@: didPressDelete", self.logTag);
    if (!self.viewItem) {
        OWSFail(@"delete should only be available when a viewItem is present");
        return;
    }

    UIAlertController *actionSheet =
        [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    [actionSheet
        addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_DELETE_TITLE", nil)
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *action) {
                                             OWSAssert([self.presentingViewController
                                                 isKindOfClass:[UINavigationController class]]);
                                             UINavigationController *navController
                                                 = (UINavigationController *)self.presentingViewController;

                                             if ([navController.topViewController
                                                     isKindOfClass:[ConversationViewController class]]) {
                                                 [self dismissSelfAnimated:YES
                                                                completion:^{
                                                                    [self.viewItem deleteAction];
                                                                }];
                                             } else if ([navController.topViewController
                                                            isKindOfClass:[MessageDetailViewController class]]) {
                                                 [self dismissSelfAnimated:NO
                                                                completion:^{
                                                                    [self.viewItem deleteAction];
                                                                }];
                                                 [navController popViewControllerAnimated:YES];
                                             } else {
                                                 OWSFail(@"Unexpected presentation context.");
                                                 [self dismissSelfAnimated:YES
                                                                completion:^{
                                                                    [self.viewItem deleteAction];
                                                                }];
                                             }
                                         }]];

    [actionSheet addAction:[OWSAlerts cancelAction]];

    [self presentViewController:actionSheet animated:YES completion:nil];
}

- (BOOL)canPerformAction:(SEL)action withSender:(nullable id)sender
{
    if (self.viewItem == nil) {
        return NO;
    }

    // Already in detail view, so no link to "info"
    if (action == self.viewItem.metadataActionSelector) {
        return NO;
    }
    return [self.viewItem canPerformAction:action];
}

- (void)copyMediaAction:(nullable id)sender
{
    if (!self.viewItem) {
        OWSFail(@"copy should only be available when a viewItem is present");
        return;
    }

    [self.viewItem copyMediaAction];
}

- (void)shareMediaAction:(nullable id)sender
{
    if (!self.viewItem) {
        OWSFail(@"share should only be available when a viewItem is present");
        return;
    }

    [self didPressShare:sender];
}

- (void)saveMediaAction:(nullable id)sender
{
    if (!self.viewItem) {
        OWSFail(@"save should only be available when a viewItem is present");
        return;
    }

    [self.viewItem saveMediaAction];
}

- (void)deleteAction:(nullable id)sender
{
    if (!self.viewItem) {
        OWSFail(@"delete should only be available when a viewItem is present");
        return;
    }

    [self didPressDelete:sender];
}

- (void)didPressPlayBarButton:(id)sender
{
    OWSAssert(self.isVideo);
    OWSAssert(self.videoPlayer);
    [self playVideo];
}

- (void)didPressPauseBarButton:(id)sender
{
    OWSAssert(self.isVideo);
    OWSAssert(self.videoPlayer);
    [self pauseVideo];
}

#pragma mark - Presentation

- (void)presentFromViewController:(UIViewController *)viewController replacingView:(UIView *)replacingView
{
    self.replacingView = replacingView;

    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    CGRect convertedRect = [replacingView convertRect:replacingView.bounds toView:window];
    self.originRect = convertedRect;

    // loadView hasn't necesarily been called yet.
    [self loadViewIfNeeded];
    [self applyInitialMediaViewConstraints];

    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:self];

    // UIModalPresentationCustom retains the current view context behind our VC, allowing us to manually
    // animate in our view, over the existing context, similar to a cross disolve, but allowing us to have
    // more fine grained control
    navController.modalPresentationStyle = UIModalPresentationCustom;
    navController.navigationBar.barTintColor = UIColor.ows_materialBlueColor;
    navController.navigationBar.translucent = NO;
    navController.navigationBar.opaque = YES;

    self.view.userInteractionEnabled = NO;

    // We want to animate the tapped media from it's position in the previous VC
    // to it's resting place in the center of this view controller.
    //
    // Rather than animating the actual media view in place, we animate the presentationView, which is a static
    // image of the media content. Animating the actual media view is problematic for a couple reasons:
    // 1. The media view ultimately lives in a zoomable scrollView. Getting both original positioning and the final positioning
    //    correct, involves manipulating the zoomScale and position simultaneously, which results in non-linear movement,
    //    especially noticeable on high resolution images.
    // 2. For Video views, the AVPlayerLayer content does not scale with the presentation animation. So you instead get a full scale
    //    video, wherein only the cropping is animated.
    // Using a simple image view allows us to address both these problems relatively easily.
    self.view.alpha = 0.0;

    self.mediaView.hidden = YES;
    self.presentationView.hidden = NO;
    self.presentationView.layer.cornerRadius = OWSMessageCellCornerRadius;

    [viewController presentViewController:navController
                                 animated:NO
                               completion:^{

                                   // 1. Fade in the entire view.
                                   [UIView animateWithDuration:0.1
                                                    animations:^{
                                                        self.replacingView.alpha = 0.0;
                                                        self.view.alpha = 1.0;
                                                    }];

                                   [self.presentationView.superview layoutIfNeeded];
                                   [self applyFinalMediaViewConstraints];

                                   // 2. Animate imageView from it's initial position, which should match where it was
                                   // in the presenting view to it's final position, front and center in this view. This
                                   // animation duration intentionally overlaps the previous
                                   [UIView animateWithDuration:0.2
                                       delay:0.08
                                       options:UIViewAnimationOptionCurveEaseOut
                                       animations:^(void) {
                                           self.presentationView.layer.cornerRadius = 0;
                                           [self.presentationView.superview layoutIfNeeded];

                                           // We must lay out once *before* we centerMediaViewConstraints
                                           // because it uses the imageView.frame to build the constraints
                                           // that will center the imageView, and then once again *after*
                                           // to ensure that the centered constraints are applied.
                                           [self centerMediaViewConstraints];
                                           [self.mediaView.superview layoutIfNeeded];
                                           self.view.backgroundColor = UIColor.whiteColor;
                                       }
                                       completion:^(BOOL finished) {
                                           // HACK: Setting the frame to itself *seems* like it should be a no-op, but
                                           // it ensures the content is drawn at the right frame. In particular I was
                                           // reproducibly some images squished (they were EXIF rotated, maybe
                                           // relateed). similar to this report:
                                           // https://stackoverflow.com/questions/27961884/swift-uiimageview-stretched-aspect
                                           self.mediaView.frame = self.mediaView.frame;

                                           // At this point our presentation view should be overlayed perfectly
                                           // with our media view. Swapping them out should be imperceptible.
                                           self.mediaView.hidden = NO;
                                           self.presentationView.hidden = YES;

                                           self.view.userInteractionEnabled = YES;

                                           if (self.isVideo) {
                                               [self playVideo];
                                           }
                                       }];
                               }];
}

- (void)dismissSelfAnimated:(BOOL)isAnimated completion:(void (^_Nullable)(void))completion
{

    self.view.userInteractionEnabled = NO;
    [UIApplication sharedApplication].statusBarHidden = NO;

    // Swapping mediaView for presentationView will be perceptible if we're not zoomed out all the way.
    if (self.scrollView.zoomScale != self.scrollView.minimumZoomScale) {
        [self.scrollView setZoomScale:self.scrollView.minimumZoomScale animated:YES];
    }

    self.mediaView.hidden = YES;
    self.presentationView.hidden = NO;

    // Move the presentationView back to it's initial position, i.e. where
    // it sits on the screen in the conversation view.
    [self applyInitialMediaViewConstraints];

    if (isAnimated) {
        [UIView animateWithDuration:0.18
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^(void) {
                             [self.presentationView.superview layoutIfNeeded];
                             self.presentationView.layer.cornerRadius = OWSMessageCellCornerRadius;

                             // In case user has hidden bars, which changes background to black.
                             self.view.backgroundColor = UIColor.whiteColor;

                         }
                         completion:nil];

        [UIView animateWithDuration:0.1
            delay:0.15
            options:UIViewAnimationOptionCurveEaseInOut
            animations:^(void) {

                OWSAssert(self.replacingView);
                self.replacingView.alpha = 1.0;

                // fade out content and toolbars
                self.navigationController.view.alpha = 0.0;
            }
            completion:^(BOOL finished) {
                [self.presentingViewController dismissViewControllerAnimated:NO completion:completion];
            }];

    } else {
        self.replacingView.alpha = 1.0;
        [self.presentingViewController dismissViewControllerAnimated:NO completion:completion];
    }
}

#pragma mark - UIScrollViewDelegate

- (nullable UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    return self.mediaView;
}

- (void)centerMediaViewConstraints
{
    OWSAssert(self.scrollView);

    CGSize scrollViewSize = self.scrollView.bounds.size;
    CGSize imageViewSize = self.mediaView.frame.size;

    CGFloat yOffset = MAX(0, (scrollViewSize.height - imageViewSize.height) / 2);
    self.mediaViewTopConstraint.constant = yOffset;
    self.mediaViewBottomConstraint.constant = yOffset;

    CGFloat xOffset = MAX(0, (scrollViewSize.width - imageViewSize.width) / 2);
    self.mediaViewLeadingConstraint.constant = xOffset;
    self.mediaViewTrailingConstraint.constant = xOffset;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView
{
    [self centerMediaViewConstraints];
    [self.view layoutIfNeeded];
}

#pragma mark - Video Playback

- (void)playVideo
{
    OWSAssert(self.videoPlayer);

    [self updateFooterBarButtonItemsWithIsPlayingVideo:YES];
    self.playVideoButton.hidden = YES;
    self.areToolbarsHidden = YES;

    [self.videoPlayer play];
}

- (void)pauseVideo
{
    OWSAssert(self.isVideo);
    OWSAssert(self.videoPlayer);

    [self updateFooterBarButtonItemsWithIsPlayingVideo:NO];
    [self.videoPlayer pause];
}

#pragma mark - OWSVideoPlayer

- (void)videoPlayerDidPlayToCompletion:(OWSVideoPlayer *)videoPlayer
{
    OWSAssert(self.isVideo);
    OWSAssert(self.videoPlayer);
    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    self.areToolbarsHidden = NO;
    self.playVideoButton.hidden = NO;

    [self updateFooterBarButtonItemsWithIsPlayingVideo:NO];
}

#pragma mark - PlayerProgressBarDelegate

- (void)playerProgressBarDidStartScrubbing:(PlayerProgressBar *)playerProgressBar
{
    OWSAssert(self.videoPlayer);
    [self.videoPlayer pause];
}

- (void)playerProgressBar:(PlayerProgressBar *)playerProgressBar scrubbedToTime:(CMTime)time
{
    OWSAssert(self.videoPlayer);
    [self.videoPlayer seekToTime:time];
}

- (void)playerProgressBar:(PlayerProgressBar *)playerProgressBar
    didFinishScrubbingAtTime:(CMTime)time
        shouldResumePlayback:(BOOL)shouldResumePlayback
{
    OWSAssert(self.videoPlayer);
    [self.videoPlayer seekToTime:time];

    if (shouldResumePlayback) {
        [self.videoPlayer play];
    }
}

#pragma mark - Saving images to Camera Roll

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    if (error) {
        DDLogWarn(@"There was a problem saving <%@> to camera roll from %s ",
            error.localizedDescription,
            __PRETTY_FUNCTION__);
    }
}

@end

NS_ASSUME_NONNULL_END
