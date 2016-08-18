//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSQRCodeScanningViewController.h"
#import "UIColor+OWS.h"

@implementation OWSQRCodeScanningViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = NSLocalizedString(@"SCAN_KEY", @"");

    self.highlightView = [[UIView alloc] init];
    self.highlightView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin
        | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.highlightView.layer.borderColor = [UIColor ows_greenColor].CGColor;
    self.highlightView.layer.borderWidth = 4;
    [self.view addSubview:self.highlightView];

    self.session = [[AVCaptureSession alloc] init];
    self.device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
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

    self.prevLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    self.prevLayer.frame = self.view.bounds;
    self.prevLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer insertSublayer:self.prevLayer atIndex:0];

    [self.session startRunning];

    [self.view bringSubviewToFront:self.highlightView];
}


- (void)captureOutput:(AVCaptureOutput *)captureOutput
    didOutputMetadataObjects:(NSArray *)metadataObjects
              fromConnection:(AVCaptureConnection *)connection
{
    CGRect highlightViewRect = CGRectZero;
    AVMetadataMachineReadableCodeObject *barCodeObject;
    NSString *detectionString = nil;
    NSArray *barCodeTypes = @[ AVMetadataObjectTypeQRCode ];

    for (AVMetadataObject *metadata in metadataObjects) {
        for (NSString *type in barCodeTypes) {
            if ([metadata.type isEqualToString:type]) {
                barCodeObject = (AVMetadataMachineReadableCodeObject *)[self.prevLayer
                    transformedMetadataObjectForMetadataObject:(AVMetadataMachineReadableCodeObject *)metadata];
                highlightViewRect = barCodeObject.bounds;
                detectionString = [(AVMetadataMachineReadableCodeObject *)metadata stringValue];
                break;
            }
        }
        if (detectionString != nil) {
            [self didDetectQRCodeWithString:detectionString];
            [self.session stopRunning];
            break;
        }
    }

    self.highlightView.frame = highlightViewRect;
}

- (void)didDetectQRCodeWithString:(NSString *)string
{
    // Override in subclass. Subclass is responsible for dismissing this view controller.
    DDLogInfo(@"Scanned QRCode with string value: %@", string);
}


@end
