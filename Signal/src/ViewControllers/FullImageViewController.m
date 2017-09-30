//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "FullImageViewController.h"
#import "AttachmentSharing.h"
#import "TSAnimatedAdapter.h"
#import "TSMessageAdapter.h"
#import "TSPhotoAdapter.h"
#import "UIColor+OWS.h"
#import "UIUtil.h"
#import "UIView+OWS.h"
#import <SignalServiceKit/NSData+Image.h>
#import <YYImage/YYImage.h>

NS_ASSUME_NONNULL_BEGIN

#define kMinZoomScale 1.0f
#define kMaxZoomScale 8.0f

#define kBackgroundAlpha 0.6f

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

@property (nonatomic) UIView *backgroundView;
@property (nonatomic) UIScrollView *scrollView;
@property (nonatomic) UIImageView *imageView;
@property (nonatomic) UIButton *shareButton;
@property (nonatomic) UIView *contentView;

@property (nonatomic) CGRect originRect;
@property (nonatomic) BOOL isPresenting;
@property (nonatomic) BOOL isAnimated;
@property (nonatomic) NSData *fileData;

@property (nonatomic) TSAttachmentStream *attachment;
@property (nonatomic) TSInteraction *interaction;
@property (nonatomic) id<OWSMessageData> messageItem;

@property (nonatomic) UIToolbar *footerBar;
@property (nonatomic) NSArray *oldMenuItems;

@end

@implementation FullImageViewController


- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment
                          fromRect:(CGRect)rect
                    forInteraction:(TSInteraction *)interaction
                       messageItem:(id<OWSMessageData>)messageItem
                        isAnimated:(BOOL)animated {
    self = [super initWithNibName:nil bundle:nil];

    if (self) {
        self.attachment  = attachment;
        self.originRect  = rect;
        self.interaction = interaction;
        self.messageItem = messageItem;
        self.isAnimated  = animated;
        self.fileData    = [NSData dataWithContentsOfURL:[attachment mediaURL]];
    }

    return self;
}

- (UIImage *)image {
    return self.attachment.image;
}

- (void)loadView {
    self.view = [AttachmentMenuView new];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:kBackgroundAlpha];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self initializeBackground];
    [self initializeContentViewAndFooterBar];
    [self initializeScrollView];
    [self initializeImageView];
    [self initializeGestureRecognizers];

    [self populateImageView:self.image];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    if ([UIMenuController sharedMenuController].isMenuVisible) {
        [[UIMenuController sharedMenuController] setMenuVisible:NO
                                                       animated:NO];
    }
}

#pragma mark - Initializers

- (void)initializeBackground {
    self.imageView.backgroundColor      = [UIColor colorWithWhite:0 alpha:kBackgroundAlpha];
    
    self.backgroundView                 = [UIView new];
    self.backgroundView.backgroundColor = [UIColor colorWithWhite:0 alpha:kBackgroundAlpha];
    [self.view addSubview:self.backgroundView];
    [self.backgroundView autoPinEdgesToSuperviewEdges];
}

- (void)initializeContentViewAndFooterBar {
    self.contentView = [UIView new];
    [self.backgroundView addSubview:self.contentView];
    [self.contentView autoPinWidthToSuperview];
    [self.contentView autoPinToTopLayoutGuideOfViewController:self withInset:0];
    
    self.footerBar = [UIToolbar new];
    _footerBar.barTintColor = [UIColor ows_signalBrandBlueColor];
    [self.footerBar setItems:@[
                               [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
                               [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                             target:self
                                                                             action:@selector(shareWasPressed:)],
                               [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
                               ]
                    animated:NO];
    [self.backgroundView addSubview:self.footerBar];
    [self.footerBar autoPinWidthToSuperview];
    [self.footerBar autoPinToBottomLayoutGuideOfViewController:self withInset:0];
    [self.footerBar autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.contentView];
}

- (void)shareWasPressed:(id)sender {
    DDLogInfo(@"%@: sharing image.", self.tag);

    [AttachmentSharing showShareUIForURL:[self.attachment mediaURL]];
}

- (void)initializeScrollView {
    self.scrollView                  = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.delegate         = self;
    self.scrollView.zoomScale        = 1.0f;
    self.scrollView.maximumZoomScale = kMaxZoomScale;
    self.scrollView.scrollEnabled    = NO;
    [self.contentView addSubview:self.scrollView];
}

- (void)initializeImageView {
    if (self.isAnimated) {
        if ([self.fileData ows_isValidImage]) {
            YYImage *animatedGif = [YYImage imageWithData:self.fileData];
            YYAnimatedImageView *imageView = [[YYAnimatedImageView alloc] init];
            imageView.image = animatedGif;
            imageView.frame = self.originRect;
            imageView.contentMode = UIViewContentModeScaleAspectFill;
            imageView.clipsToBounds = YES;
            self.imageView = imageView;
        } else {
            self.imageView = [[UIImageView alloc] initWithFrame:self.originRect];
        }
    } else {
        // Present the static image using standard UIImageView
        self.imageView                              = [[UIImageView alloc] initWithFrame:self.originRect];
        self.imageView.contentMode                  = UIViewContentModeScaleAspectFill;
        self.imageView.userInteractionEnabled       = YES;
        self.imageView.clipsToBounds                = YES;
        self.imageView.layer.allowsEdgeAntialiasing = YES;
        // Use trilinear filters for better scaling quality at
        // some performance cost.
        self.imageView.layer.minificationFilter = kCAFilterTrilinear;
        self.imageView.layer.magnificationFilter = kCAFilterTrilinear;
    }

    [self.scrollView addSubview:self.imageView];
}

- (void)populateImageView:(UIImage *)image {
    if (image && !self.isAnimated) {
        self.imageView.image = image;
    }
}

- (void)initializeGestureRecognizers {
    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                action:@selector(imageDismissGesture:)];
    singleTap.delegate = self;
    [self.view addGestureRecognizer:singleTap];
    
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                action:@selector(imageDismissGesture:)];
    doubleTap.numberOfTapsRequired = 2;
    doubleTap.delegate = self;
    [self.view addGestureRecognizer:doubleTap];
    
    // UISwipeGestureRecognizer supposedly supports multiple directions,
    // but in practice it works better if you use a separate GR for each
    // direction.
    for (NSNumber *direction in @[
                                  @(UISwipeGestureRecognizerDirectionRight),
                                  @(UISwipeGestureRecognizerDirectionLeft),
                                  @(UISwipeGestureRecognizerDirectionUp),
                                  @(UISwipeGestureRecognizerDirectionDown),
                                  ]) {
        UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self
                                                                                    action:@selector(imageDismissGesture:)];
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

- (void)imageDismissGesture:(UIGestureRecognizer *)sender {
  if (sender.state == UIGestureRecognizerStateRecognized) {
    [self dismiss];
  }
}

- (void)longPressGesture:(UIGestureRecognizer *)sender {
    // We "eagerly" respond when the long press begins, not when it ends.
    if (sender.state == UIGestureRecognizerStateBegan) {

        [self.view becomeFirstResponder];
        
        if ([UIMenuController sharedMenuController].isMenuVisible) {
            [[UIMenuController sharedMenuController] setMenuVisible:NO
                                                           animated:NO];
        }

        NSArray *menuItems = @[
                               [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_COPY_ACTION", @"Short name for edit menu item to copy contents of media message.")
                                                          action:@selector(copyAttachment:)],
                               [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_SAVE_ACTION", @"Short name for edit menu item to save contents of media message.")
                                                          action:@selector(saveAttachment:)],
                               [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_SHARE_ACTION", @"Short name for edit menu item to share contents of media message.")
                                                          action:@selector(shareAttachment:)],
                               ];
        if (!self.oldMenuItems) {
            self.oldMenuItems = [UIMenuController sharedMenuController].menuItems;
        }
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

- (void)performEditingActionWithSelector:(SEL)selector {
    OWSAssert(self.messageItem.messageType == TSIncomingMessageAdapter ||
              self.messageItem.messageType == TSOutgoingMessageAdapter);
    OWSAssert([self.messageItem isMediaMessage]);
    OWSAssert([self.messageItem isKindOfClass:[TSMessageAdapter class]]);
    OWSAssert([self.messageItem conformsToProtocol:@protocol(OWSMessageEditing)]);
    OWSAssert([[self.messageItem media] isKindOfClass:[TSPhotoAdapter class]] ||
              [[self.messageItem media] isKindOfClass:[TSAnimatedAdapter class]]);
    
    OWSAssert([self.messageItem canPerformEditingAction:selector]);
    [self.messageItem performEditingAction:selector];
}

- (void)copyAttachment:(id)sender {
    [self performEditingActionWithSelector:NSSelectorFromString(@"copy:")];
}

- (void)saveAttachment:(id)sender {
    [self performEditingActionWithSelector:NSSelectorFromString(@"save:")];
}

- (void)shareAttachment:(id)sender {
    [self performEditingActionWithSelector:NSSelectorFromString(@"share:")];
}

#pragma mark - Presentation

- (void)presentFromViewController:(UIViewController *)viewController {
    _isPresenting                    = YES;
    self.view.userInteractionEnabled = NO;
    [self.view addSubview:self.imageView];
    self.modalPresentationStyle = UIModalPresentationOverCurrentContext;
    self.view.alpha             = 0;

    [viewController
        presentViewController:self
                     animated:NO
                   completion:^{
                       UIWindow *window = [UIApplication sharedApplication].keyWindow;
                       // During the presentation animation, we want to seamlessly animate the image
                       // from its location in the conversation view.  To do so, we need a
                       // consistent coordinate system, so we pass the `originRect` in the
                       // coordinate system of the window.
                       self.imageView.frame = [self.view convertRect:self.originRect
                                                            fromView:window];
                       
                     [UIView animateWithDuration:0.25f
                         delay:0
                         options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                         animations:^() {
                             self.view.alpha      = 1.0f;
                             // During the presentation animation, we want to seamlessly animate the image
                             // to its resting location in this view.  We use `resizedFrameForImageView`
                             // to determine its size "at rest" in the content view, and then convert
                             // from the content view's coordinate system to the root view coordinate
                             // system because the image view is temporarily hosted by the root view during
                             // the presentation animation.
                             self.imageView.frame = [self resizedFrameForImageView:self.image.size];
                             self.imageView.center = [self.contentView convertPoint:self.contentView.center
                                                                           fromView:self.contentView];
                         }
                         completion:^(BOOL completed) {
                           self.scrollView.frame = self.contentView.bounds;
                           [self.scrollView addSubview:self.imageView];
                           [self updateLayouts];
                           self.view.userInteractionEnabled = YES;
                           _isPresenting                    = NO;
                         }];
                     [UIUtil modalCompletionBlock]();
                   }];
}

- (void)dismiss {

    // Restore the edit menu items if necessary.
    if (self.oldMenuItems) {
        [UIMenuController sharedMenuController].menuItems = self.oldMenuItems;
    }

    self.view.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.25f
        delay:0
        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveLinear
        animations:^() {
          self.backgroundView.backgroundColor = [UIColor clearColor];
          self.scrollView.alpha               = 0;
          self.view.alpha                     = 0;
        }
        completion:^(BOOL completed) {
          [self.presentingViewController dismissViewControllerAnimated:NO completion:nil];
        }];
}

#pragma mark - Update Layout

- (void)viewDidLayoutSubviews {
    [self updateLayouts];
}

- (void)updateLayouts {
    if (_isPresenting) {
        return;
    }

    self.scrollView.frame        = self.contentView.bounds;
    self.imageView.frame         = [self resizedFrameForImageView:self.image.size];
    self.scrollView.contentSize  = self.imageView.frame.size;
    self.scrollView.contentInset = [self contentInsetForScrollView:self.scrollView.zoomScale];
}

#pragma mark - Resizing

- (CGRect)resizedFrameForImageView:(CGSize)imageSize {
    CGRect frame = self.contentView.bounds;
    CGSize screenSize =
        CGSizeMake(frame.size.width * self.scrollView.zoomScale, frame.size.height * self.scrollView.zoomScale);
    CGSize targetSize = screenSize;

    if ([self isImagePortrait]) {
        if ([self getAspectRatioForCGSize:screenSize] < [self getAspectRatioForCGSize:imageSize]) {
            targetSize.width = screenSize.height / [self getAspectRatioForCGSize:imageSize];
        } else {
            targetSize.height = screenSize.width * [self getAspectRatioForCGSize:imageSize];
        }
    } else {
        if ([self getAspectRatioForCGSize:screenSize] > [self getAspectRatioForCGSize:imageSize]) {
            targetSize.height = screenSize.width * [self getAspectRatioForCGSize:imageSize];
        } else {
            targetSize.width = screenSize.height / [self getAspectRatioForCGSize:imageSize];
        }
    }

    frame.size   = targetSize;
    frame.origin = CGPointMake(0, 0);
    return frame;
}

- (UIEdgeInsets)contentInsetForScrollView:(CGFloat)targetZoomScale {
    UIEdgeInsets inset = UIEdgeInsetsZero;

    CGSize boundsSize  = self.scrollView.bounds.size;
    CGSize contentSize = self.image.size;
    CGSize minSize;

    if ([self isImagePortrait]) {
        if ([self getAspectRatioForCGSize:boundsSize] < [self getAspectRatioForCGSize:contentSize]) {
            minSize.height = boundsSize.height;
            minSize.width  = minSize.height / [self getAspectRatioForCGSize:contentSize];
        } else {
            minSize.width  = boundsSize.width;
            minSize.height = minSize.width * [self getAspectRatioForCGSize:contentSize];
        }
    } else {
        if ([self getAspectRatioForCGSize:boundsSize] > [self getAspectRatioForCGSize:contentSize]) {
            minSize.width  = boundsSize.width;
            minSize.height = minSize.width * [self getAspectRatioForCGSize:contentSize];
        } else {
            minSize.height = boundsSize.height;
            minSize.width  = minSize.height / [self getAspectRatioForCGSize:contentSize];
        }
    }

    CGSize finalSize = self.view.bounds.size;

    minSize.width *= targetZoomScale;
    minSize.height *= targetZoomScale;

    if (minSize.height > finalSize.height && minSize.width > finalSize.width) {
        inset = UIEdgeInsetsZero;
    } else {
        CGFloat dy = boundsSize.height - minSize.height;
        CGFloat dx = boundsSize.width - minSize.width;

        dy = (dy > 0) ? dy : 0;
        dx = (dx > 0) ? dx : 0;

        inset.top    = dy / 2.0f;
        inset.bottom = dy / 2.0f;
        inset.left   = dx / 2.0f;
        inset.right  = dx / 2.0f;
    }
    return inset;
}

#pragma mark - UIScrollViewDelegate

- (nullable UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    return self.imageView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    scrollView.contentInset = [self contentInsetForScrollView:scrollView.zoomScale];

    if (self.scrollView.scrollEnabled == NO) {
        self.scrollView.scrollEnabled = YES;
    }
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(nullable UIView *)view atScale:(CGFloat)scale
{
    self.scrollView.scrollEnabled = (scale > 1);
    self.scrollView.contentInset  = [self contentInsetForScrollView:scale];
}

#pragma mark - Utility

- (BOOL)isImagePortrait {
    return ([self getAspectRatioForCGSize:self.image.size] > 1.0f);
}

- (CGFloat)getAspectRatioForCGSize:(CGSize)size {
    return size.height / size.width;
}


#pragma mark - Saving images to Camera Roll

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    if (error) {
        DDLogWarn(@"There was a problem saving <%@> to camera roll from %s ",
                  error.localizedDescription,
                  __PRETTY_FUNCTION__);
    }
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
