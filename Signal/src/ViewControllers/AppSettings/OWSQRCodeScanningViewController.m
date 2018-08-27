//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSQRCodeScanningViewController.h"
#import "OWSBezierPathView.h"
#import "UIColor+OWS.h"
#import "UIView+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSQRCodeScanningViewController ()

@property (atomic) ZXCapture *capture;
@property (nonatomic) BOOL captureEnabled;
@property (nonatomic) UIView *maskingView;

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

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    _captureEnabled = NO;

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
        CGFloat margin = ScaleFromIPhone5To7Plus(8.f, 16.f);
        CGFloat radius = MIN(bounds.size.width, bounds.size.height) * 0.5f - margin;

        // Center the circle's bounding rectangle
        CGRect circleRect = CGRectMake(
            bounds.size.width * 0.5f - radius, bounds.size.height * 0.5f - radius, radius * 2.f, radius * 2.f);
        UIBezierPath *circlePath = [UIBezierPath bezierPathWithRoundedRect:circleRect cornerRadius:radius];
        [path appendPath:circlePath];
        [path setUsesEvenOddFillRule:YES];

        layer.path = path.CGPath;
        layer.fillRule = kCAFillRuleEvenOdd;
        layer.fillColor = [UIColor grayColor].CGColor;
        layer.opacity = 0.5f;
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

- (void)startCapture
{
    self.captureEnabled = YES;
    if (!self.capture) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            self.capture = [[ZXCapture alloc] init];
            self.capture.camera = self.capture.back;
            self.capture.focusMode = AVCaptureFocusModeContinuousAutoFocus;
            self.capture.layer.frame = self.view.bounds;
            self.capture.delegate = self;

            dispatch_async(dispatch_get_main_queue(), ^{
                [self.view.layer addSublayer:self.capture.layer];
                [self.view bringSubviewToFront:self.maskingView];
                [self.capture start];
            });
        });
    } else {
        [self.capture start];
    }
}

- (void)stopCapture
{
    self.captureEnabled = NO;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
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
