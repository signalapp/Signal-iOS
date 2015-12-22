//
//  PresentIdentityQRCodeViewController.m
//  Signal-iOS
//
//  Created by Christine Corbett Moran on 3/30/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "NSData+Base64.h"
#import "PresentIdentityQRCodeViewController.h"
#import "UIImage+normalizeImage.h"


@implementation PresentIdentityQRCodeViewController


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}


- (void)viewDidLoad {
    [super viewDidLoad];

    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];

    [filter setDefaults];

    [filter setValue:[[self.identityKey base64EncodedString] dataUsingEncoding:NSUTF8StringEncoding]
              forKey:@"inputMessage"];

    CIImage *outputImage = [filter outputImage];

    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:outputImage fromRect:[outputImage extent]];

    UIImage *image = [UIImage imageWithCGImage:cgImage scale:1. orientation:UIImageOrientationUp];

    // Resize without interpolating
    UIImage *resized = [image resizedWithQuality:kCGInterpolationNone rate:5.0];

    self.qrCodeView.image      = resized;
    _yourFingerprintLabel.text = NSLocalizedString(@"FINGERPRINT_YOURS", @"");
    CGImageRelease(cgImage);
}

@end
