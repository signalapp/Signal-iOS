//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

@class OWSQRCodeScanningViewController;

@protocol OWSQRScannerDelegate

- (void)controller:(OWSQRCodeScanningViewController *)controller didDetectQRCodeWithString:(NSString *)scannedString;

@end

@interface OWSQRCodeScanningViewController : UIViewController <AVCaptureMetadataOutputObjectsDelegate>

@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDevice *device;
@property (nonatomic, strong) AVCaptureDeviceInput *input;
@property (nonatomic, strong) AVCaptureMetadataOutput *output;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *prevLayer;

@property (nonatomic, strong) UIView *highlightView;
@property (nonatomic, weak) UIViewController<OWSQRScannerDelegate> *scanDelegate;

// HACK to resize views after embedding. Better would be to specify layout of preview layer as constraints.
- (void)resizeViews;

@end
