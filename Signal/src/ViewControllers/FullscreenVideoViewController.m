//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "FLAnimatedImage.h"
#import "FullscreenVideoViewController.h"
#import "UIView+OWS.h"
#import "ViewControllerUtils.h"

#pragma mark - FullscreenMediaAnimator

@interface FullscreenVideoAnimator : NSObject <UIViewControllerAnimatedTransitioning>

- (instancetype)initWithImage:(UIImage *)image originRect:(CGRect)origin;

@property UIImageView *imageView;
@property UIImage *image;
@property CGRect origin;

@property (nonatomic) BOOL dismiss;

@end

@implementation FullscreenVideoAnimator

- (instancetype)initWithImage:(UIImage *)image originRect:(CGRect)origin {
    self = [super init];
    if (self) {
        self.image = image;
        self.origin = origin;
    }
    return self;
}

- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext {
    return 0.3;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext {
    UIView *fromView = [transitionContext viewForKey:UITransitionContextFromViewKey];
    UIView *toView = [transitionContext viewForKey:UITransitionContextToViewKey];
    UIWindow *window = [UIApplication sharedApplication].keyWindow;

    CGRect startFrame, endFrame;
    UIView *imgParent = transitionContext.containerView;

    [transitionContext.containerView addSubview:toView];
    [self createImageView];

    if (self.dismiss) {
        self.imageView.alpha = 1;
        startFrame = fromView.frame;
        endFrame = [window convertRect:self.origin toView:imgParent];
    } else {
        startFrame = [window convertRect:self.origin toView:imgParent];
        endFrame = toView.frame;
    }
    
    [imgParent addSubview:self.imageView];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.frame = startFrame;

    [UIView animateKeyframesWithDuration:[self transitionDuration:transitionContext]
                                   delay:0
                                 options:0
                              animations: ^{
        if (self.dismiss) {
            [UIView addKeyframeWithRelativeStartTime:0 relativeDuration:0.333 animations:^{
                fromView.backgroundColor = [UIColor clearColor];
            }];
            [UIView addKeyframeWithRelativeStartTime:0.333 relativeDuration:0.667 animations:^{
                self.imageView.frame = endFrame;
            }];
        } else {
            [UIView addKeyframeWithRelativeStartTime:0 relativeDuration:0.667 animations:^{
                self.imageView.frame = endFrame;
            }];
            [UIView addKeyframeWithRelativeStartTime:0.667 relativeDuration:0.333 animations:^{
                toView.backgroundColor = [UIColor blackColor];
            }];
        }
    } completion:^(BOOL finished) {
        if (self.dismiss) {
            [self.imageView removeFromSuperview];
        }

        BOOL wasCancelled = [transitionContext transitionWasCancelled];
        [transitionContext completeTransition:!wasCancelled];
    }];
}

- (void)createImageView {
    if (!self.imageView) {
        self.imageView = [[UIImageView alloc] initWithImage:self.image];
    }
}

// Allow the view controller to show/hide the transiton image so that it
// can coordinate with the media player.
- (void)hideImage {
    self.imageView.alpha = 0;
}
- (void)showImage {
    self.imageView.alpha = 1;
}

@end


#pragma mark - FullVideoViewController Private

@interface FullscreenVideoViewController ()

@property (nonatomic) CGRect originRect;
@property (nonatomic) TSAttachmentStream *attachment;
@property (nonatomic) FullscreenVideoAnimator *animator;
@property MPMoviePlayerController *player;

@end

@implementation FullscreenVideoViewController

#pragma mark - Initializers

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment
                          fromRect:(CGRect)rect {
    self = [super initWithNibName:nil bundle:nil];

    if (self) {
        self.attachment  = attachment;
        self.originRect  = rect;
        self.transitioningDelegate = self;
    }

    return self;
}

#pragma mark - UIViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.player = [[MPMoviePlayerController alloc] initWithContentURL:self.attachment.mediaURL];
    // We want the player to look like it is in fullscreen mode
    // but not actually to be in fullscreen mode because that
    // comes with screen flashes as it transitions in and out
    // (even if we pass animated:NO).
    self.player.controlStyle = MPMovieControlStyleFullscreen;
    self.player.shouldAutoplay = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(moviePlayerDidFinish:)
                                                 name:MPMoviePlayerPlaybackDidFinishNotification
                                               object:self.player];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(moviePlayerLoadStateChange:)
                                                 name:MPMoviePlayerLoadStateDidChangeNotification
                                               object:self.player];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(dismissIfDoneState:)
                                                 name:MPMoviePlayerPlaybackStateDidChangeNotification
                                               object:self.player];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Other Setup

- (void) initAnimator {
    self.animator = [[FullscreenVideoAnimator alloc] initWithImage:self.attachment.image
                                                        originRect:self.originRect];
  
}

#pragma mark - Presentation

- (void)presentFromViewController:(UIViewController *)viewController {
    [self initAnimator];
  
    // Though the player is entirely opaque this is probably our best bet for being able to zoom
    // back out to the original location because it leaves the views in MessagesViewController
    // unchanged instead of necessitating saving and restoring a scroll offset in that class.
    self.modalPresentationStyle = UIModalPresentationOverCurrentContext;
    [ViewControllerUtils setAudioIgnoresHardwareMuteSwitch:YES];

    [viewController presentViewController:self animated:YES completion:^{
        [self.player prepareToPlay];
        [self.view addSubview:self.player.view];
        self.player.view.frame = self.view.bounds;
        self.player.shouldAutoplay = YES;
    }];
}

- (void)dismiss {
    [ViewControllerUtils setAudioIgnoresHardwareMuteSwitch:NO];
    [self.animator showImage];
    [self.player.view removeFromSuperview];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Notifications

- (void)moviePlayerLoadStateChange:(NSNotification *)notification {
    // Wait until the player is ready to play to hide the image
    // minimizing black flash to the extent possible.
    if (self.player.loadState != MPMovieLoadStateUnknown) {
        [self.animator hideImage];
    } else {
        [self dismissIfDoneState:notification];
    }
}

- (void)dismissIfDoneState:(NSNotification *)notification {
    // This covers the case when the user taps the back or next button unloading the video
    if (self.player.loadState == MPMovieLoadStateUnknown &&
        self.player.playbackState == MPMoviePlaybackStateStopped) {
        [self dismiss];
    }
}

- (void)moviePlayerDidFinish:(NSNotification *)notification {
    // This covers the user tapping the done button
    if (notification.userInfo) {
        NSNumber *reason = [notification.userInfo valueForKey:MPMoviePlayerPlaybackDidFinishReasonUserInfoKey];
        if ([reason intValue] == MPMovieFinishReasonUserExited) {
            [self dismiss];
        }
    }
}

#pragma mark - UIViewControllerTransitionDelegate

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                  presentingController:(UIViewController *)presenting
                                                                      sourceController:(UIViewController *)source {
    self.animator.dismiss = NO;
    return self.animator;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    self.animator.dismiss = YES;
    return self.animator;
}


#pragma mark - Logging

+ (NSString *)tag {
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag {
    return self.class.tag;
}

@end
