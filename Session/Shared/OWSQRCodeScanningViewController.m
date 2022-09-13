//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSQRCodeScanningViewController.h"
#import "OWSBezierPathView.h"
#import "UIColor+OWS.h"
#import "UIView+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSQRCodeScanningViewController ()

@property (atomic) ZXCapture *capture;
@property (nonatomic) BOOL captureEnabled;
@property (nonatomic) BOOL hasCompletedCaptureSetup;
@property (nonatomic) UIView *maskingView;
@property (nonatomic) dispatch_queue_t captureQueue;

@end

#pragma mark -

@implementation OWSQRCodeScanningViewController

- (void)dealloc
{
    [self.capture.layer removeFromSuperlayer];
}

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _captureEnabled = NO;
    _captureQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    _captureEnabled = NO;
    _captureQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    return self;
}

- (void)loadView
{
    [super loadView];

    OWSBezierPathView *maskingView = [OWSBezierPathView new];
    self.maskingView = maskingView;
    [maskingView setConfigureShapeLayerBlock:^(CAShapeLayer *layer, CGRect bounds) {
        // Add a circular mask
        UIBezierPath *path = [UIBezierPath bezierPathWithRect:bounds];
        CGFloat margin = ScaleFromIPhone5To7Plus(24.f, 48.f);
        CGFloat radius = MIN(bounds.size.width, bounds.size.height) * 0.5f - margin;

        // Center the circle's bounding rectangle
        CGRect circleRect = CGRectMake(
            bounds.size.width * 0.5f - radius, bounds.size.height * 0.5f - radius, radius * 2.f, radius * 2.f);
        UIBezierPath *circlePath = [UIBezierPath bezierPathWithRoundedRect:circleRect cornerRadius:16.f];
        [path appendPath:circlePath];
        [path setUsesEvenOddFillRule:YES];

        layer.path = path.CGPath;
        layer.fillRule = kCAFillRuleEvenOdd;
        layer.fillColor = UIColor.lokiDarkestGray.CGColor;
        layer.opacity = 0.32f;
    }];
    [self.view addSubview:maskingView];
    [maskingView ows_autoPinToSuperviewEdges];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    if (self.captureEnabled) {
        [self startCapture];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self stopCapture];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    
    // Note: When accessing 'capture.layer' if the setup hasn't been completed it
    // will result in a layout being triggered which creates an infinite loop, this
    // check prevents that case
    if (self.hasCompletedCaptureSetup) {
        self.capture.layer.frame = self.view.bounds;
    }
}

- (void)startCapture
{
    self.captureEnabled = YES;
    
    // Note: The simulator doesn't support video but if we do try to start an
    // AVCaptureSession it seems to hang on that particular thread indefinitely
    // this will prevent us from trying to start a session on the simulator
#if TARGET_OS_SIMULATOR
#else
    if (!self.capture) {
        dispatch_async(self.captureQueue, ^{
            self.capture = [[ZXCapture alloc] init];
            self.capture.camera = self.capture.back;
            self.capture.focusMode = AVCaptureFocusModeContinuousAutoFocus;
            self.capture.delegate = self;
            [self.capture start];
            
            // Note: When accessing the 'layer' for the first time it will create
            // an instance of 'AVCaptureVideoPreviewLayer', this can hang a little
            // so we do this on the background thread first
            if (self.capture.layer) {}
            
            dispatch_async(dispatch_get_main_queue(), ^{
                self.capture.layer.frame = self.view.bounds;
                [self.view.layer addSublayer:self.capture.layer];
                [self.view bringSubviewToFront:self.maskingView];
                self.hasCompletedCaptureSetup = YES;
            });
        });
    }
    else {
        dispatch_async(self.captureQueue, ^{
            [self.capture start];
        });
    }
#endif
}

- (void)stopCapture
{
    self.captureEnabled = NO;
    dispatch_async(self.captureQueue, ^{
        [self.capture stop];
    });
}

- (void)captureResult:(ZXCapture *)capture result:(ZXResult *)result
{
    if (!self.captureEnabled) {
        return;
    }
    [self stopCapture];

    // Vibrate
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);

    if (self.scanDelegate) {
        if ([self.scanDelegate respondsToSelector:@selector(controller:didDetectQRCodeWithData:)]) {
            OWSLogInfo(@"Scanned Data Code.");
            ZXByteArray *byteArray = result.resultMetadata[@(kResultMetadataTypeByteSegments)][0];
            NSData *decodedData = [NSData dataWithBytes:byteArray.array length:byteArray.length];

            [self.scanDelegate controller:self didDetectQRCodeWithData:decodedData];
        }

        if ([self.scanDelegate respondsToSelector:@selector(controller:didDetectQRCodeWithString:)]) {
            OWSLogInfo(@"Scanned String Code.");
            [self.scanDelegate controller:self didDetectQRCodeWithString:result.text];
        }
    }
}

@end

NS_ASSUME_NONNULL_END
