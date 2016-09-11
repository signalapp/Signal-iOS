//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSQRCodeScanningViewController.h"
#import "UIColor+OWS.h"
//#import <ZXingObjC/ZXingObjC.h>


@interface OWSQRCodeScanningViewController ()

@property (nonatomic) BOOL captureEnabled;
@property (nonatomic, strong) ZXCapture *capture;
@property UIView *maskingView;
@property CALayer *maskingLayer;


@end

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

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    _captureEnabled = NO;

    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.maskingView = [[UIView alloc] initWithFrame:self.view.frame];
    [self.view addSubview:self.maskingView];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    if (self.captureEnabled) {
        [self startCapture];
    }
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self layoutMaskingView];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self stopCapture];
}

- (void)layoutMaskingView
{
    self.maskingView.frame = self.view.frame;
    if (self.maskingLayer) {
        [self.maskingLayer removeFromSuperlayer];
    }
    self.maskingLayer = [self buildCircularMaskingLayer];
    [self.maskingView.layer addSublayer:self.maskingLayer];
}

- (void)startCapture
{
    self.captureEnabled = YES;
    if (!self.capture) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            self.capture = [[ZXCapture alloc] init];
            self.capture.camera = self.capture.back;
            self.capture.focusMode = AVCaptureFocusModeContinuousAutoFocus;
            self.capture.layer.frame = self.view.frame;
            self.capture.delegate = self;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.view.layer addSublayer:self.capture.layer];
                [self.view bringSubviewToFront:self.maskingView];
            });
        });
    }
    [self.capture start];
}

- (void)stopCapture
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.capture stop];
    });
}

- (CAShapeLayer *)buildCircularMaskingLayer
{
    // Add a circular mask
    UIBezierPath *path = [UIBezierPath
        bezierPathWithRoundedRect:CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height)
                     cornerRadius:0];
    CGFloat verticalMargin = 8.0;
    CGFloat radius = self.view.frame.size.height / 2.0f - verticalMargin;

    // Center the circle's bounding rectangle
    CGFloat horizontalMargin = (self.view.frame.size.width - 2.0f * radius) / 2.0f;
    UIBezierPath *circlePath = [UIBezierPath
        bezierPathWithRoundedRect:CGRectMake(horizontalMargin, verticalMargin, 2.0f * radius, 2.0f * radius)
                     cornerRadius:radius];
    [path appendPath:circlePath];
    [path setUsesEvenOddFillRule:YES];

    CAShapeLayer *fillLayer = [CAShapeLayer layer];
    fillLayer.path = path.CGPath;
    fillLayer.fillRule = kCAFillRuleEvenOdd;
    fillLayer.fillColor = [UIColor grayColor].CGColor;
    fillLayer.opacity = 0.5;
    return fillLayer;
}

- (void)captureResult:(ZXCapture *)capture result:(ZXResult *)result
{
    [self stopCapture];

    // TODO bounding rectangle

    // Vibrate
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);

    if (self.scanDelegate) {
        if ([self.scanDelegate respondsToSelector:@selector(controller:didDetectQRCodeWithData:)]) {
            DDLogInfo(@"%@ Scanned Data Code.", self.tag);
            ZXByteArray *byteArray = result.resultMetadata[@(kResultMetadataTypeByteSegments)][0];
            NSData *decodedData = [NSData dataWithBytes:byteArray.array length:byteArray.length];

            [self.scanDelegate controller:self didDetectQRCodeWithData:decodedData];
        }

        if ([self.scanDelegate respondsToSelector:@selector(controller:didDetectQRCodeWithString:)]) {
            DDLogInfo(@"%@ Scanned String Code.", self.tag);
            [self.scanDelegate controller:self didDetectQRCodeWithString:result.text];
        }
    }
}

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
