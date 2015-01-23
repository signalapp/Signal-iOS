//
//  ScanIdentityBarcodeViewController.m
//  Signal-iOS
//
//  Created by Christine Corbett Moran on 3/29/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "ScanIdentityBarcodeViewController.h"
#import "NSData+Base64.h"
#import "NSData+hexString.h"
#import "UIColor+OWS.h"



@implementation ScanIdentityBarcodeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Scan key";
    
    self.highlightView = [[UIView alloc] init];
    self.highlightView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleBottomMargin;
    self.highlightView.layer.borderColor = [UIColor ows_greenColor].CGColor;
    self.highlightView.layer.borderWidth = 4;
    [self.view addSubview:self.highlightView];
    
    self.label = [[UILabel alloc] init];
    self.label.frame = CGRectMake(0, self.view.bounds.size.height - 40, self.view.bounds.size.width, 40);
    self.label.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
    self.label.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.65];
    self.label.textColor = [UIColor whiteColor];
    self.label.textAlignment = NSTextAlignmentCenter;
    self.label.text = @"(none)";
    [self.view addSubview:self.label];
    
    self.session = [[AVCaptureSession alloc] init];
    self.device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error = nil;
    
    self.input = [AVCaptureDeviceInput deviceInputWithDevice:self.device error:&error];
    if (self.input) {
        [self.session addInput:self.input];
    } else {
        NSLog(@"Error: %@", error);
    }
    
    self.output = [[AVCaptureMetadataOutput alloc] init];
    [self.output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    [self.session addOutput:self.output];
    
    self.output.metadataObjectTypes = [self.output availableMetadataObjectTypes];
    
    self.prevLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    self.prevLayer.frame = self.view.bounds;
    self.prevLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer addSublayer:self.prevLayer];
    
    [self.session startRunning];
    
    [self.view bringSubviewToFront:self.highlightView];
    [self.view bringSubviewToFront:self.label];
}


- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
    CGRect highlightViewRect = CGRectZero;
    AVMetadataMachineReadableCodeObject *barCodeObject;
    NSString *detectionString = nil;
    NSArray *barCodeTypes = @[AVMetadataObjectTypeQRCode];
    
    for (AVMetadataObject *metadata in metadataObjects) {
        NSLog(@"metadata %@",metadata);
        for (NSString *type in barCodeTypes) {
            if ([metadata.type isEqualToString:type]) {
                barCodeObject = (AVMetadataMachineReadableCodeObject *)[self.prevLayer transformedMetadataObjectForMetadataObject:(AVMetadataMachineReadableCodeObject *)metadata];
                highlightViewRect = barCodeObject.bounds;
                detectionString = [(AVMetadataMachineReadableCodeObject *)metadata stringValue];
                break;
            }
        }
        if (detectionString != nil) {
            self.label.text = detectionString;
            NSData* detectionData = [NSData dataFromBase64String:detectionString];
            if([detectionData isEqualToData:self.identityKey]) {
                self.label.text = @"verified!";
            }
            else {
                self.label.text = @"identity keys do not match";
            }
            [self.session stopRunning];
            break;
        }
        else {
            self.label.text = @"searching...";
        }
    }
    if([self.label.text isEqualToString:@"verified!"]) {
        [self performSegueWithIdentifier:@"UnwindToIdentityKeyWasVerifiedSegue" sender:self];
    }

    self.highlightView.frame = highlightViewRect;
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






@end




