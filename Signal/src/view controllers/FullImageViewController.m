//
//  FullImageViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 11/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "FullImageViewController.h"
#import "DJWActionSheet.h"

@interface FullImageViewController () <UIScrollViewDelegate>

@end

@implementation FullImageViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _fullImageView.image = _image;
    
    [self initializeScrollView];
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Initializer

-(void)initializeScrollView
{
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    [doubleTap setNumberOfTapsRequired:2];
    [_pinchView addGestureRecognizer:doubleTap];
    
    _pinchView.delegate = self;
    _pinchView.minimumZoomScale=0.9f;
    _pinchView.maximumZoomScale=3.0f;
    _pinchView.showsVerticalScrollIndicator = NO;
    _pinchView.showsHorizontalScrollIndicator = NO;
    _pinchView.contentSize=CGSizeMake(CGRectGetWidth(_fullImageView.frame), CGRectGetHeight(_fullImageView.frame));
}

#pragma mark - IBAction

-(IBAction)close:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(IBAction)more:(id)sender
{
    [DJWActionSheet showInView:self.view
                     withTitle:@"Options"
             cancelButtonTitle:@"Cancel"
        destructiveButtonTitle:nil
             otherButtonTitles:@[@"Save to Camera Roll", @"Delete"]
                      tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                          if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                              NSLog(@"User Cancelled");
                              
                          } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex) {
                              NSLog(@"Destructive button tapped");
                          }else {
                              NSLog(@"The user tapped button at index: %li", (long)tappedButtonIndex);
                          }
                      }];

}

#pragma mark - Scroll View

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    return _fullImageView;
}

- (IBAction)handleDoubleTap:(id)sender {
    
    CGFloat desiredScale = [self doubleTapDestinationZoomScale];
    CGPoint center = [(UITapGestureRecognizer*)sender locationInView:_fullImageView];
    CGRect zoomRect = [self zoomRectForScale:desiredScale withCenter:center];
    
    [_pinchView zoomToRect:zoomRect animated:YES];
    [_pinchView setZoomScale:desiredScale animated:YES];
}


- (CGRect)zoomRectForScale:(CGFloat)scale withCenter:(CGPoint)center {
    CGRect zoomRect;
    
    zoomRect.size.height = CGRectGetHeight(_pinchView.frame) / scale;
    zoomRect.size.width  = CGRectGetWidth(_pinchView.frame)  / scale;
    
    zoomRect.origin.x    = center.x - ((CGRectGetWidth(zoomRect) / 2.0f));
    zoomRect.origin.y    = center.y - ((CGRectGetHeight(zoomRect) / 2.0f));
    
    return zoomRect;
}

- (CGFloat)doubleTapDestinationZoomScale
{
    BOOL cond = _pinchView.zoomScale == _pinchView.maximumZoomScale;
    
    return cond ? _pinchView.minimumZoomScale : _pinchView.maximumZoomScale;
}

#pragma mark - Layout

-(void)centerInSuperview
{
    CGRect frame = _fullImageView.frame;
    CGRect superviewFrame = self.view.frame;
    
    CGFloat dy = (CGRectGetHeight(superviewFrame) - CGRectGetHeight(frame)) / 2.0f;
    frame.origin.y = dy;
    
    CGFloat dx = (CGRectGetWidth(superviewFrame) - CGRectGetWidth(frame)) / 2.0f;
    frame.origin.x = dx;
    
    _fullImageView.frame = frame;
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
