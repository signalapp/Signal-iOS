//
//  FullImageViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 11/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "FullImageViewController.h"
#import "DJWActionSheet+OWS.h"
#import "TSAttachmentStream.h"
#import "UIUtil.h"
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseViewMappings.h>
#import <SwipeView/SwipeView.h>
#import "TSStorageManager.h"
#import "TSDatabaseView.h"
#import "TSAdapterCacheManager.h"
#import "TSMessageAdapter.h"
#import "TSAttachmentAdapter.h"

#define kImageViewCornerRadius 5.0f

#define kMinZoomScale 1.0f
#define kMaxZoomScale 8.0f
#define kTargetDoubleTapZoom 3.0f

#define kBackgroundAlpha 0.6f

@interface FullImageViewController () <SwipeViewDelegate,SwipeViewDataSource,UIScrollViewDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, strong) YapDatabaseConnection *uiDatabaseConnection;
@property (nonatomic, strong) YapDatabaseViewMappings *imageMappings;

@property (nonatomic, strong) SwipeView *swipeView;

@property (nonatomic, strong) UIView *backgroundView;

@property (nonatomic, strong) UIButton *shareButton;

@property BOOL isPresenting;

@property TSInteraction      *interaction;
@property TSThread *thread;

@end

@implementation FullImageViewController


- (instancetype)initWithInteraction:(TSInteraction*)interaction {
    self = [super initWithNibName:nil bundle:nil];
    
    if  (self) {
        self.interaction     = interaction;
        self.thread          = [[TSThread alloc] initWithUniqueId:interaction.uniqueThreadId];
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self initializeBackground];
    [self initializeSwipeView];
    
    [self.uiDatabaseConnection beginLongLivedReadTransaction];
    
    self.imageMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[[self threadGrouping]]
                                                                    view:TSImageAttachmentDatabaseViewExtensionName];
    [self.uiDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction){
        [self.imageMappings updateWithTransaction:transaction];
        
        __block NSInteger gotoItem;
        [[transaction extension:TSImageAttachmentDatabaseViewExtensionName] enumerateRowsInGroup:[self threadGrouping] usingBlock:^(NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop) {
            if ([key isEqualToString:self.interaction.uniqueId]) {
                gotoItem = (NSInteger)index;
                *stop = YES;
            }
        }];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.swipeView reloadData];
            [self.swipeView scrollToItemAtIndex:gotoItem duration:0l];
        });
    }];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}
#pragma mark Database delegates

- (YapDatabaseConnection *)uiDatabaseConnection {
    NSAssert([NSThread isMainThread], @"Must access uiDatabaseConnection on main thread!");
    if (!_uiDatabaseConnection) {
        YapDatabase *database = TSStorageManager.sharedManager.database;
        _uiDatabaseConnection = [database newConnection];
        [_uiDatabaseConnection beginLongLivedReadTransaction];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(yapDatabaseModified:)
                                                     name:YapDatabaseModifiedNotification
                                                   object:database];
    }
    return _uiDatabaseConnection;
}

- (void)yapDatabaseModified:(NSNotification *)notification
{
    DDLogInfo(@"Database changed and i haven't done a thing");
}


#pragma mark - Initializers

- (void)initializeSwipeView
{
    self.swipeView = [[SwipeView alloc] initWithFrame:self.view.bounds];
    self.swipeView.itemsPerPage = 1;
    
    self.swipeView.dataSource = self;
    self.swipeView.delegate = self;
    
    [self.view addSubview:self.swipeView];
}

- (void)initializeBackground
{
    self.view.backgroundColor           = [UIColor colorWithWhite:0 alpha:kBackgroundAlpha];
    self.view.autoresizingMask          = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundView                 = [[UIView alloc] initWithFrame:CGRectInset(self.view.bounds, -512, -512)];
    self.backgroundView.backgroundColor = [UIColor colorWithWhite:0 alpha:kBackgroundAlpha];
    
    [self.view addSubview:self.backgroundView];
}

- (void) initializeShareButton
{
    CGFloat buttonRadius = 50.0f;
    CGFloat x = 14.0f;
    CGFloat y = self.view.bounds.size.height - buttonRadius - 10.0f;
    
    self.shareButton = [[UIButton alloc]initWithFrame:CGRectMake(x, y, buttonRadius, buttonRadius)];
    [self.shareButton addTarget:self action:@selector(shareButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.shareButton setImage:[UIImage imageNamed:@"savephoto"] forState:UIControlStateNormal];
    
    [self.view addSubview:self.shareButton];
}

#pragma mark - Gesture Recognizers

- (void)imageDoubleTapped:(UITapGestureRecognizer*)doubleTap
{
    UIScrollView *currentScrollView = (UIScrollView*) doubleTap.view;

    CGPoint tap = [doubleTap locationInView:doubleTap.view];
    CGPoint convertCoord = [currentScrollView convertPoint:tap fromView:doubleTap.view];
    CGRect targetZoomRect;
    UIEdgeInsets targetInsets;
    
    CGSize zoom ;
    
    if (currentScrollView.zoomScale == 1.0f) {
        zoom = CGSizeMake(self.swipeView.bounds.size.width / kTargetDoubleTapZoom, self.swipeView.bounds.size.height / kTargetDoubleTapZoom);
        targetZoomRect = CGRectMake(convertCoord.x - (zoom.width/2.0f), convertCoord.y - (zoom.height/2.0f), zoom.width, zoom.height);
        targetInsets = [self contentInsetForScrollView:kTargetDoubleTapZoom andScrollView:currentScrollView];
    } else {
        zoom = CGSizeMake(self.swipeView.bounds.size.width * currentScrollView.zoomScale, self.swipeView.bounds.size.height * currentScrollView.zoomScale);
        targetZoomRect = CGRectMake(convertCoord.x - (zoom.width/2.0f), convertCoord.y - (zoom.height/2.0f), zoom.width, zoom.height);
        targetInsets = [self contentInsetForScrollView:1.0f andScrollView:currentScrollView];
    }
    
    self.view.userInteractionEnabled = NO;
    
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        currentScrollView.contentInset = targetInsets;
        self.view.userInteractionEnabled = YES;
    }];
    [currentScrollView zoomToRect:targetZoomRect animated:YES];
    [CATransaction commit];

}

- (void)imageSingleTapped:(UITapGestureRecognizer*)singleTap
{
    [self dismiss];
}

#pragma mark - Presentation

-(void)presentFromViewController:(UIViewController*)viewController
{
    _isPresenting = YES;
    self.view.userInteractionEnabled = NO;
    self.modalPresentationStyle = UIModalPresentationOverCurrentContext;
    self.view.alpha = 0;
    
    [viewController presentViewController:self animated:NO completion:^{
            [UIView animateWithDuration:0.4f
                                  delay:0
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut
                             animations:^(){
                                 self.view.alpha = 1.0f;
                           } completion:^(BOOL completed){
                                 [self initializeShareButton];
                                 self.view.userInteractionEnabled = YES;
                                 _isPresenting = NO;
                             }];
        [UIUtil modalCompletionBlock]();
    }];

}

- (void)dismiss
{
    self.view.userInteractionEnabled = NO;
    
    UIScrollView *currentScrollView = [self currentlyDisplayedScrollView];
    
    [UIView animateWithDuration:0.4f
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut
                     animations:^(){
                         self.backgroundView.backgroundColor = [UIColor clearColor];
                         currentScrollView.alpha = 0;
                         self.view.alpha = 0;
                     } completion:^(BOOL completed){
                         [self.presentingViewController dismissViewControllerAnimated:NO completion:nil];
                     }];
}


#pragma mark - Update Layout

- (void) updateLayoutsForScrollView:(UIScrollView*)scrollView andImageView:(UIImageView*)imageView
{
    UIImage *image = [imageView image];
    
    scrollView.frame        = self.swipeView.bounds;
    imageView.frame         = [self resizedFrameForImageView:image.size andScrollView:scrollView];
    
    scrollView.contentSize  = imageView.frame.size;
    scrollView.contentInset = [self contentInsetForScrollView:scrollView.zoomScale andScrollView:scrollView];
}


#pragma mark - Resizing

- (CGRect)resizedFrameForImageView:(CGSize)imageSize andScrollView:(UIScrollView*)scrollView {
    CGRect frame = self.swipeView.bounds;
    CGSize screenSize = CGSizeMake(frame.size.width * scrollView.zoomScale, frame.size.height * scrollView.zoomScale);
    CGSize targetSize = screenSize;
    
    UIImage *image = [self imageViewFromScrollView:scrollView].image;
    
    if ([self isImagePortrait:image]) {
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
    
    frame.size = targetSize;
    frame.origin = CGPointMake(0, 0);
    return frame;
}

- (UIEdgeInsets)contentInsetForScrollView:(CGFloat)targetZoomScale andScrollView:(UIScrollView*)scrollView {
    UIImage *image = [self imageViewFromScrollView:scrollView].image;
    
    UIEdgeInsets inset = UIEdgeInsetsZero;
    
    CGSize boundsSize = scrollView.bounds.size;
    CGSize contentSize = image.size;
    CGSize minSize;
    
    if ([self isImagePortrait:image]) {
        if ([self getAspectRatioForCGSize:boundsSize] < [self getAspectRatioForCGSize:contentSize]) {
            minSize.height = boundsSize.height;
            minSize.width = minSize.height / [self getAspectRatioForCGSize:contentSize];
        } else {
            minSize.width = boundsSize.width;
            minSize.height = minSize.width * [self getAspectRatioForCGSize:contentSize];
        }
    } else {
        if ([self getAspectRatioForCGSize:boundsSize] > [self getAspectRatioForCGSize:contentSize]) {
            minSize.width = boundsSize.width;
            minSize.height =  minSize.width * [self getAspectRatioForCGSize:contentSize];
        } else {
            minSize.height = boundsSize.height;
            minSize.width = minSize.height / [self getAspectRatioForCGSize:contentSize];
        }
    }
    
    CGSize finalSize = self.swipeView.bounds.size;

    minSize.width *= targetZoomScale;
    minSize.height *= targetZoomScale;
    
    if (minSize.height > finalSize.height && minSize.width > finalSize.width) {
        inset = UIEdgeInsetsZero;
    } else {
        CGFloat dy = boundsSize.height - minSize.height;
        CGFloat dx = boundsSize.width - minSize.width;
        
        dy = (dy > 0) ? dy : 0;
        dx = (dx > 0) ? dx : 0;
        
        inset.top    = dy/2.0f;
        inset.bottom = dy/2.0f;
        inset.left   = dx/2.0f;
        inset.right  = dx/2.0f;
    }
    
    return inset;
}

#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return [self imageViewFromScrollView:scrollView];
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
 
    scrollView.contentInset = [self contentInsetForScrollView:scrollView.zoomScale andScrollView:scrollView];
    
    if (scrollView.scrollEnabled == NO) {
        scrollView.scrollEnabled = YES;
        self.swipeView.scrollEnabled = NO;
    }
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(CGFloat)scale {
    scrollView.scrollEnabled = (scale > 1);
    
    if (scrollView.scrollEnabled == YES) {
        self.swipeView.scrollEnabled = NO;
    } else {
        self.swipeView.scrollEnabled = YES;
    }
    
    scrollView.contentInset = [self contentInsetForScrollView:scale andScrollView:scrollView];
}

#pragma mark - SwipeView Delegate & DataSource
- (CGSize)swipeViewItemSize:(SwipeView *)swipeView
{
    return self.view.frame.size;
}
- (NSInteger)numberOfItemsInSwipeView:(SwipeView *)swipeView
{
    return (NSInteger)[self.imageMappings numberOfItemsInGroup:[self threadGrouping]];
}

- (UIView *)swipeView:(SwipeView *)swipeView viewForItemAtIndex:(NSInteger)index reusingView:(UIView *)view
{
    UIScrollView *scrollViewWithImage = (UIScrollView*) view;
    
    if (scrollViewWithImage == nil) {
        scrollViewWithImage = [self makeScrollView];
    }
    
    UIImage *image = [self imageAtIndex:index];
    UIImageView *imageView = [self imageViewFromScrollView:scrollViewWithImage];
    [self populateImageView:imageView withImage:image];

    [self updateLayoutsForScrollView:scrollViewWithImage andImageView:imageView];
    
    return scrollViewWithImage;
}


#pragma mark - Utility
- (UIScrollView*)currentlyDisplayedScrollView
{
    return (UIScrollView*)[self.swipeView currentItemView];
}

- (UIImageView*)imageViewFromScrollView:(UIScrollView*)scrollView
{
    if ([scrollView.subviews count] == 0) {
        return nil;
    }
    
    return [scrollView.subviews objectAtIndex:0];
}

- (UIScrollView*)makeScrollView
{
    //base scrollView
    UIScrollView *scrollView    = [[UIScrollView alloc] initWithFrame:self.swipeView.bounds];
    scrollView.delegate         = self;
    scrollView.zoomScale        = 1.0f;
    scrollView.maximumZoomScale = kMaxZoomScale;
    scrollView.scrollEnabled    = NO;
    
    //imageView in subviews position 0
    UIImageView *imageView                 = [[UIImageView alloc]initWithFrame:self.swipeView.bounds];
    imageView.layer.cornerRadius           = kImageViewCornerRadius;
    imageView.contentMode                  = UIViewContentModeScaleAspectFill;
    imageView.userInteractionEnabled       = YES;
    imageView.clipsToBounds                = YES;
    imageView.layer.allowsEdgeAntialiasing = YES;
    imageView.backgroundColor              = [UIColor colorWithWhite:0 alpha:kBackgroundAlpha];
    
    [scrollView addSubview:imageView];
    
    //tap recognizers for zomming and dismissing this modal
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(imageDoubleTapped:)];
    doubleTap.numberOfTapsRequired = 2;
    
    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(imageSingleTapped:)];
    [singleTap requireGestureRecognizerToFail:doubleTap];
    
    doubleTap.delegate = self;
    singleTap.delegate = self;
    
    [scrollView addGestureRecognizer:singleTap];
    [scrollView addGestureRecognizer:doubleTap];
    
    return scrollView;
}


- (void)populateImageView:(UIImageView*) imageView withImage:(UIImage*)image
{
    if (image) {
        imageView.image = image;
    }
}

- (NSString*) threadGrouping
{
    return self.thread.uniqueId;
}

- (TSInteraction*) interactionAtIndex:(NSInteger)index
{
    __block TSInteraction *interaction = nil;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        interaction = [[transaction extension:TSImageAttachmentDatabaseViewExtensionName] objectAtRow:(NSUInteger)index inSection:0 withMappings:self.imageMappings];
    }];
    
    return interaction;
}

- (UIImage*)imageAtIndex:(NSInteger)index {
    TSInteraction *interaction = [self interactionAtIndex:index];
    TSAdapterCacheManager *manager = [TSAdapterCacheManager sharedManager];
    
    if (![manager containsCacheEntryForInteractionId:interaction.uniqueId]) {
        [manager cacheAdapter:[TSMessageAdapter messageViewDataWithInteraction:interaction inThread:self.thread] forInteractionId:interaction.uniqueId];
    }
    
    TSMessageAdapter *message = [manager adapterForInteractionId:interaction.uniqueId];
    TSAttachmentAdapter *messageMedia = (TSAttachmentAdapter*)[message media];
    return ((UIImageView*) [messageMedia mediaView]).image;
}

- (BOOL)isImagePortrait:(UIImage*)image
{
    return ([self getAspectRatioForCGSize:image.size] > 1.0f);
}

- (CGFloat)getAspectRatioForCGSize:(CGSize)size
{
    return size.height / size.width;
}

#pragma mark - Actions

-(void)shareButtonTapped:(UIButton*)sender
{
    /*
    [DJWActionSheet showInView:self.view withTitle:nil cancelButtonTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"") destructiveButtonTitle:NSLocalizedString(@"TXT_DELETE_TITLE", @"") otherButtonTitles:@[NSLocalizedString(@"CAMERA_ROLL_SAVE_BUTTON", @""), NSLocalizedString(@"CAMERA_ROLL_COPY_BUTTON", @"")] tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
        if (tappedButtonIndex == actionSheet.cancelButtonIndex) {

        } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex){
            __block TSInteraction *interaction = [self interaction];
            [self dismissViewControllerAnimated:YES completion:^{
                [interaction remove];
            }];
            
        } else {
            switch (tappedButtonIndex) {
                case 0:
                    UIImageWriteToSavedPhotosAlbum(self.image, self, @selector(image:didFinishSavingWithError:contextInfo:), nil);
                    break;
                case 1:
                    [[UIPasteboard generalPasteboard] setImage:self.image];
                    break;
                default:
                    DDLogWarn(@"Illegal Action sheet field #%ld <%s>",(long)tappedButtonIndex, __PRETTY_FUNCTION__);
                    break;
            }
        }
    }];
     */
}

#pragma mark - Saving images to Camera Roll

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error
  contextInfo:(void *)contextInfo
{
    if (error)
    {
        DDLogWarn(@"There was a problem saving <%@> to camera roll from %s ", error.localizedDescription ,__PRETTY_FUNCTION__);
    }
}

@end
