//
//  PresentIdentityQRCodeViewController.m
//  Signal-iOS
//
//  Created by Christine Corbett Moran on 3/30/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "PresentIdentityQRCodeViewController.h"
#import "NSData+Base64.h"


@implementation PresentIdentityQRCodeViewController


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}



- (void) viewDidLoad {
    [super viewDidLoad];
    
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    
    [filter setDefaults];

    [filter setValue:[[self.identityKey base64EncodedString] dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];
    
    CIImage *outputImage = [filter outputImage];
    
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:outputImage fromRect:[outputImage extent]];
    
    UIImage *image = [UIImage imageWithCGImage:cgImage scale:1. orientation:UIImageOrientationUp];
    
    // Resize without interpolating
    UIImage *resized = [self resizeImage:image withQuality:kCGInterpolationNone rate:5.0];
    
    self.qrCodeView.image = resized;
    
    CGImageRelease(cgImage);
}

#pragma mark - Action
- (IBAction)closeButtonAction:(id)sender
{
    [UIView animateWithDuration:0.6 delay:0. options:UIViewAnimationOptionCurveEaseInOut animations:^{
        [self.view setAlpha:0];
    } completion:^(BOOL succeeded){
        [self dismissViewControllerAnimated:YES completion:nil];
    }];
    
}


#pragma mark - Private

- (UIImage *)resizeImage:(UIImage *)image withQuality:(CGInterpolationQuality)quality rate:(CGFloat)rate {
	UIImage *resized = nil;
	CGFloat width = image.size.width * rate;
	CGFloat height = image.size.height * rate;
    
	UIGraphicsBeginImageContext(CGSizeMake(width, height));
	CGContextRef context = UIGraphicsGetCurrentContext();
	CGContextSetInterpolationQuality(context, quality);
	[image drawInRect:CGRectMake(0, 0, width, height)];
	resized = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
    
	return resized;
}

@end
