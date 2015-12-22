//
//  ScanIdentityBarcodeViewController.h
//  Signal-iOS
//
//  Created by Christine Corbett Moran on 3/29/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
@interface ScanIdentityBarcodeViewController : UIViewController <AVCaptureMetadataOutputObjectsDelegate>

@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDevice *device;
@property (nonatomic, strong) AVCaptureDeviceInput *input;
@property (nonatomic, strong) AVCaptureMetadataOutput *output;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *prevLayer;

@property (nonatomic, strong) UIView *highlightView;
@property (nonatomic, strong) NSData *identityKey;
@end
