//
//  FullImageViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 11/11/14.
//  Animated GIF support added by Mike Okner (@mikeokner) on 11/27/15.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <AssetsLibrary/AssetsLibrary.h>
#import "DJWActionSheet+OWS.h"
#import "FLAnimatedImage.h"
#import "FullImageViewController.h"
#import "UIUtil.h"

#define kImageViewCornerRadius 5.0f

#define kMinZoomScale 1.0f
#define kMaxZoomScale 8.0f
#define kTargetDoubleTapZoom 3.0f

#define kBackgroundAlpha 0.6f

@interface FullImageViewController () <UIScrollViewDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, strong) UIView *backgroundView;

@property (nonatomic, strong) UIScrollView *scrollView;

@property (nonatomic, strong) UIImageView *imageView;

@property (nonatomic, strong) UITapGestureRecognizer *singleTap;
@property (nonatomic, strong) UITapGestureRecognizer *doubleTap;

@property (nonatomic, strong) UIButton *shareButton;

@property CGRect originRect;
@property BOOL isPresenting;
@property BOOL isAnimated;
@property NSData *fileData;

@property TSAttachmentStream *attachment;
@property TSInteraction *interaction;

@end

@implementation FullImageViewController


- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment
                          fromRect:(CGRect)rect
                    forInteraction:(TSInteraction *)interaction
                        isAnimated:(BOOL)animated {
    self = [super initWithNibName:nil bundle:nil];

    if (self) {
        self.attachment  = attachment;
        self.originRect  = rect;
        self.interaction = interaction;
        self.isAnimated  = animated;
        self.fileData    = [NSData dataWithContentsOfURL:[attachment mediaURL]];
    }

    return self;
}

- (UIImage *)image {
    return self.attachment.image;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self initializeBackground];
    [self initializeScrollView];
    [self initializeImageView];
    [self initializeGestureRecognizers];

    [self populateImageView:self.image];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}


#pragma mark - Initializers

- (void)initializeBackground {
    self.imageView.backgroundColor      = [UIColor colorWithWhite:0 alpha:kBackgroundAlpha];
    self.view.backgroundColor           = [UIColor colorWithWhite:0 alpha:kBackgroundAlpha];
    self.view.autoresizingMask          = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundView                 = [[UIView alloc] initWithFrame:CGRectInset(self.view.bounds, -512, -512)];
    self.backgroundView.backgroundColor = [UIColor colorWithWhite:0 alpha:kBackgroundAlpha];

    [self.view addSubview:self.backgroundView];
}

- (void)initializeScrollView {
    self.scrollView                  = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.delegate         = self;
    self.scrollView.zoomScale        = 1.0f;
    self.scrollView.maximumZoomScale = kMaxZoomScale;
    self.scrollView.scrollEnabled    = NO;
    [self.view addSubview:self.scrollView];
}

- (void)initializeImageView {
    if (self.isAnimated) {
        // Present the animated image using Flipboard/FLAnimatedImage
        FLAnimatedImage *animatedGif   = [FLAnimatedImage animatedImageWithGIFData:self.fileData];
        FLAnimatedImageView *imageView = [[FLAnimatedImageView alloc] init];
        imageView.animatedImage        = animatedGif;
        imageView.frame                = self.originRect;
        imageView.contentMode          = UIViewContentModeScaleAspectFill;
        imageView.clipsToBounds        = YES;
        self.imageView                 = imageView;
    } else {
        // Present the static image using standard UIImageView
        self.imageView                              = [[UIImageView alloc] initWithFrame:self.originRect];
        self.imageView.layer.cornerRadius           = kImageViewCornerRadius;
        self.imageView.contentMode                  = UIViewContentModeScaleAspectFill;
        self.imageView.userInteractionEnabled       = YES;
        self.imageView.clipsToBounds                = YES;
        self.imageView.layer.allowsEdgeAntialiasing = YES;
    }

    [self.scrollView addSubview:self.imageView];
}

- (void)populateImageView:(UIImage *)image {
    if (image && !self.isAnimated) {
        self.imageView.image = image;
    }
}

- (void)initializeGestureRecognizers {
    self.doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(imageDoubleTapped:)];
    self.doubleTap.numberOfTapsRequired = 2;

    self.singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(imageSingleTapped:)];
    [self.singleTap requireGestureRecognizerToFail:self.doubleTap];

    self.singleTap.delegate = self;
    self.doubleTap.delegate = self;

    [self.view addGestureRecognizer:self.singleTap];
    [self.view addGestureRecognizer:self.doubleTap];
}

- (void)initializeShareButton {
    CGFloat buttonRadius = 50.0f;
    CGFloat x            = 14.0f;
    CGFloat y            = self.view.bounds.size.height - buttonRadius - 10.0f;

    self.shareButton = [[UIButton alloc] initWithFrame:CGRectMake(x, y, buttonRadius, buttonRadius)];
    [self.shareButton addTarget:self action:@selector(shareButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.shareButton setImage:[UIImage imageNamed:@"savephoto"] forState:UIControlStateNormal];

    [self.view addSubview:self.shareButton];
}

#pragma mark - Gesture Recognizers

- (void)imageDoubleTapped:(UITapGestureRecognizer *)doubleTap {
    CGPoint tap          = [doubleTap locationInView:doubleTap.view];
    CGPoint convertCoord = [self.scrollView convertPoint:tap fromView:doubleTap.view];
    CGRect targetZoomRect;
    UIEdgeInsets targetInsets;

    CGSize zoom;

    if (self.scrollView.zoomScale == 1.0f) {
        zoom = CGSizeMake(self.view.bounds.size.width / kTargetDoubleTapZoom,
                          self.view.bounds.size.height / kTargetDoubleTapZoom);
        targetZoomRect = CGRectMake(
            convertCoord.x - (zoom.width / 2.0f), convertCoord.y - (zoom.height / 2.0f), zoom.width, zoom.height);
        targetInsets = [self contentInsetForScrollView:kTargetDoubleTapZoom];
    } else {
        zoom = CGSizeMake(self.view.bounds.size.width * self.scrollView.zoomScale,
                          self.view.bounds.size.height * self.scrollView.zoomScale);
        targetZoomRect = CGRectMake(
            convertCoord.x - (zoom.width / 2.0f), convertCoord.y - (zoom.height / 2.0f), zoom.width, zoom.height);
        targetInsets = [self contentInsetForScrollView:1.0f];
    }

    self.view.userInteractionEnabled = NO;

    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
      self.scrollView.contentInset     = targetInsets;
      self.view.userInteractionEnabled = YES;
    }];
    [self.scrollView zoomToRect:targetZoomRect animated:YES];
    [CATransaction commit];
}

- (void)imageSingleTapped:(UITapGestureRecognizer *)singleTap {
    [self dismiss];
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
                     [UIView animateWithDuration:0.4f
                         delay:0
                         options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut
                         animations:^() {
                           self.view.alpha      = 1.0f;
                           self.imageView.frame = [self resizedFrameForImageView:self.image.size];
                           self.imageView.center =
                               CGPointMake(self.view.bounds.size.width / 2.0f, self.view.bounds.size.height / 2.0f);
                         }
                         completion:^(BOOL completed) {
                           self.scrollView.frame = self.view.bounds;
                           [self.scrollView addSubview:self.imageView];
                           [self updateLayouts];
                           [self initializeShareButton];
                           self.view.userInteractionEnabled = YES;
                           _isPresenting                    = NO;
                         }];
                     [UIUtil modalCompletionBlock]();
                   }];
}

- (void)dismiss {
    self.view.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.4f
        delay:0
        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut
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

    self.scrollView.frame        = self.view.bounds;
    self.imageView.frame         = [self resizedFrameForImageView:self.image.size];
    self.scrollView.contentSize  = self.imageView.frame.size;
    self.scrollView.contentInset = [self contentInsetForScrollView:self.scrollView.zoomScale];
}


#pragma mark - Resizing

- (CGRect)resizedFrameForImageView:(CGSize)imageSize {
    CGRect frame = self.view.bounds;
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

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    scrollView.contentInset = [self contentInsetForScrollView:scrollView.zoomScale];

    if (self.scrollView.scrollEnabled == NO) {
        self.scrollView.scrollEnabled = YES;
    }
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(CGFloat)scale {
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

#pragma mark - Actions

- (void)shareButtonTapped:(UIButton *)sender {
    [DJWActionSheet showInView:self.view
                     withTitle:nil
             cancelButtonTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
        destructiveButtonTitle:NSLocalizedString(@"TXT_DELETE_TITLE", @"")
             otherButtonTitles:@[
                 NSLocalizedString(@"CAMERA_ROLL_SAVE_BUTTON", @""),
                 NSLocalizedString(@"CAMERA_ROLL_COPY_BUTTON", @"")
             ]
                      tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                        if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                        } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex) {
                            __block TSInteraction *interaction = [self interaction];
                            [self dismissViewControllerAnimated:YES
                                                     completion:^{
                                                       [interaction remove];
                                                     }];

                        } else {
                            switch (tappedButtonIndex) {
                                case 0: {
                                    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
                                    [library writeImageDataToSavedPhotosAlbum:self.fileData
                                                                     metadata:nil
                                                              completionBlock:^(NSURL *assetURL, NSError *error) {
                                                                if (error) {
                                                                    DDLogWarn(@"Error Saving image to photo album: %@",
                                                                              error);
                                                                }
                                                              }];
                                    break;
                                }
                                case 1:
                                    [[UIPasteboard generalPasteboard] setImage:self.image];
                                    break;
                                default:
                                    DDLogWarn(@"Illegal Action sheet field #%ld <%s>",
                                              (long)tappedButtonIndex,
                                              __PRETTY_FUNCTION__);
                                    break;
                            }
                        }
                      }];
}

#pragma mark - Saving images to Camera Roll

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    if (error) {
        DDLogWarn(@"There was a problem saving <%@> to camera roll from %s ",
                  error.localizedDescription,
                  __PRETTY_FUNCTION__);
    }
}

@end
