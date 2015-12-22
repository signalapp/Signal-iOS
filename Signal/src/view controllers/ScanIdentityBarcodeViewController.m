//
//  ScanIdentityBarcodeViewController.m
//  Signal-iOS
//
//  Created by Christine Corbett Moran on 3/29/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "NSData+Base64.h"
#import "ScanIdentityBarcodeViewController.h"
#import "UIColor+OWS.h"


@implementation ScanIdentityBarcodeViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"SCAN_KEY", @"");

    self.highlightView                  = [[UIView alloc] init];
    self.highlightView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin |
                                          UIViewAutoresizingFlexibleRightMargin |
                                          UIViewAutoresizingFlexibleBottomMargin;
    self.highlightView.layer.borderColor = [UIColor ows_greenColor].CGColor;
    self.highlightView.layer.borderWidth = 4;
    [self.view addSubview:self.highlightView];

    self.session   = [[AVCaptureSession alloc] init];
    self.device    = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error = nil;

    self.input = [AVCaptureDeviceInput deviceInputWithDevice:self.device error:&error];
    if (self.input) {
        [self.session addInput:self.input];
    } else {
        DDLogDebug(@"Error: %@", error);
    }

    self.output = [[AVCaptureMetadataOutput alloc] init];
    [self.output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    [self.session addOutput:self.output];

    self.output.metadataObjectTypes = [self.output availableMetadataObjectTypes];

    self.prevLayer              = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    self.prevLayer.frame        = self.view.bounds;
    self.prevLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer insertSublayer:self.prevLayer atIndex:0];

    [self.session startRunning];

    [self.view bringSubviewToFront:self.highlightView];
}


- (void)captureOutput:(AVCaptureOutput *)captureOutput
    didOutputMetadataObjects:(NSArray *)metadataObjects
              fromConnection:(AVCaptureConnection *)connection {
    CGRect highlightViewRect = CGRectZero;
    AVMetadataMachineReadableCodeObject *barCodeObject;
    NSString *detectionString = nil;
    NSArray *barCodeTypes     = @[ AVMetadataObjectTypeQRCode ];

    for (AVMetadataObject *metadata in metadataObjects) {
        for (NSString *type in barCodeTypes) {
            if ([metadata.type isEqualToString:type]) {
                barCodeObject = (AVMetadataMachineReadableCodeObject *)[self.prevLayer
                    transformedMetadataObjectForMetadataObject:(AVMetadataMachineReadableCodeObject *)metadata];
                highlightViewRect = barCodeObject.bounds;
                detectionString   = [(AVMetadataMachineReadableCodeObject *)metadata stringValue];
                break;
            }
        }
        if (detectionString != nil) {
            NSData *detectionData = [NSData dataFromBase64String:detectionString];

            NSString *dialogTitle;
            NSString *dialogDescription;

            if ([detectionData isEqualToData:self.identityKey]) {
                dialogTitle       = NSLocalizedString(@"SCAN_KEY_VERIFIED_TITLE", @"");
                dialogDescription = NSLocalizedString(@"SCAN_KEY_VERIFIED_TEXT", @"");
            } else {
                dialogTitle       = NSLocalizedString(@"SCAN_KEY_CONFLICT_TITLE", @"");
                dialogDescription = NSLocalizedString(@"SCAN_KEY_CONFLICT_TEXT", @"");
            }

            [self.session stopRunning];
            UIAlertController *controller = [UIAlertController alertControllerWithTitle:dialogTitle
                                                                                message:dialogDescription
                                                                         preferredStyle:UIAlertControllerStyleAlert];

            [self presentViewController:controller
                               animated:YES
                             completion:^{
                               [self performSelector:@selector(dismissScannerAfterSuccesfullScan)
                                          withObject:nil
                                          afterDelay:5];
                             }];

            break;
        }
    }

    self.highlightView.frame = highlightViewRect;
}

#pragma mark - Action

- (void)dismissScannerAfterSuccesfullScan {
    [self dismissViewControllerAnimated:YES
                             completion:^{
                               [self closeButtonAction:nil];
                             }];
}

- (IBAction)closeButtonAction:(id)sender {
    [self performSegueWithIdentifier:@"UnwindToIdentityKeyWasVerifiedSegue" sender:self];
}

@end
