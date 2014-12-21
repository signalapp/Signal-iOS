//
//  FullImageViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 11/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "FullImageViewController.h"
#import "DJWActionSheet.h"

#define kImageViewCornerRadius 5.0f

#define kMinZoomScale 1.0f
#define kMaxZoomScale 5.0f

@interface FullImageViewController () <UIScrollViewDelegate>

@property (nonatomic, strong) UIView *backgroundView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImage* image;
@property CGRect originRect;

@property BOOL isPresenting;

@end

@implementation FullImageViewController


- (instancetype)initWithImage:(UIImage*)image fromRect:(CGRect)rect {
    self = [super initWithNibName:nil bundle:nil];
    
    if  (self) {
        self.image = image;
        self.imageView.image = image;
        self.originRect = rect;
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self initializeBackground];
    [self initializeScrollView];
    [self initializeImageView];
    
    [self populateImageView:self.image];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}


#pragma mark - Initializers

-(void)initializeBackground
{
    
    self.view.backgroundColor           = [UIColor blackColor];
    self.view.autoresizingMask          = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundView                 = [[UIView alloc] initWithFrame:CGRectInset(self.view.bounds, -512, -512)];
    self.backgroundView.backgroundColor = [UIColor blackColor];
    self.backgroundView.alpha           = 0;
    
    [self.view addSubview:self.backgroundView];
}

-(void)initializeScrollView
{
    self.scrollView                  = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.delegate         = self;
    self.scrollView.zoomScale        = 1.0f;
    self.scrollView.maximumZoomScale = kMaxZoomScale;
    self.scrollView.scrollEnabled    = NO;
    [self.view addSubview:self.scrollView];
}

- (void)initializeImageView
{
    self.imageView                              = [[UIImageView alloc]initWithFrame:[self resizedFrameForImageView:self.image.size]];
    self.imageView.layer.cornerRadius           = kImageViewCornerRadius;
    self.imageView.contentMode                  = UIViewContentModeScaleAspectFill;
    self.imageView.userInteractionEnabled       = YES;
    self.imageView.clipsToBounds                = YES;
    self.imageView.layer.allowsEdgeAntialiasing = YES;
    [self.scrollView addSubview:self.imageView];

}

-(void)populateImageView:(UIImage*)image
{
    if (image) {
        self.imageView.image = image;
    }
}

#pragma mark - Presentation
-(void)presentFromViewController:(UIViewController*)viewController
{
    _isPresenting = YES;
    self.view.userInteractionEnabled = NO;
    [self.view addSubview:self.imageView];

    [viewController presentViewController:self animated:NO completion:^{

        self.imageView.frame = self.originRect;
        
            [UIView animateWithDuration:0.6f
                                  delay:0
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut
                             animations:^(){
                                 self.imageView.frame = [self resizedFrameForImageView:self.image.size];
                                 self.imageView.center = CGPointMake(self.view.bounds.size.width/2.0f, self.view.bounds.size.height/2.0f);
                             }
                             completion:^(BOOL completed){
                                 self.scrollView.frame = self.view.bounds;
                                 [self.scrollView addSubview:self.imageView];
                                 [self updateLayouts];
                                 self.view.userInteractionEnabled = YES;
                                 _isPresenting = NO;
                             }];
    }];

}

#pragma mark - Update Layout

- (void)viewDidLayoutSubviews
{
    [self updateLayouts];
}


- (void) updateLayouts
{
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
    CGSize screenSize = CGSizeMake(frame.size.width * self.scrollView.zoomScale, frame.size.height * self.scrollView.zoomScale);
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
    
    frame.size = targetSize;
    frame.origin = CGPointMake(0, 0);
    return frame;
}

- (UIEdgeInsets)contentInsetForScrollView:(CGFloat)targetZoomScale {
    UIEdgeInsets inset = UIEdgeInsetsZero;
    
    CGSize boundsSize = self.scrollView.bounds.size;
    CGSize contentSize = self.image.size;
    CGSize minSize;
    
    if ([self isImagePortrait]) {
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
        
        inset.top    = dy/2.0f;
        inset.bottom = dy/2.0f;
        inset.left   = dx/2.0f;
        inset.right  = dx/2.0f;
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
    self.scrollView.contentInset = [self contentInsetForScrollView:scale];
}

#pragma mark - Utility

- (BOOL)isImagePortrait
{
    return ([self getAspectRatioForCGSize:self.image.size] > 1.0f);
}

- (CGFloat)getAspectRatioForCGSize:(CGSize)size
{
    return size.height / size.width;
}

@end
