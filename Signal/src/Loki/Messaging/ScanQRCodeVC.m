#import "ScanQRCodeVC.h"
#import "Session-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface ScanQRCodeVC ()

@property (nonatomic) OWSQRCodeScanningViewController *qrCodeScanningVC;

@end

@implementation ScanQRCodeVC

- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Background color
    self.view.backgroundColor = Theme.backgroundColor;
    // QR code scanning VC
    self.qrCodeScanningVC = [OWSQRCodeScanningViewController new];
    self.qrCodeScanningVC.scanDelegate = self.delegate;
    [self.view addSubview:self.qrCodeScanningVC.view];
    [self.qrCodeScanningVC.view autoPinEdgeToSuperviewEdge:ALEdgeLeading];
    [self.qrCodeScanningVC.view autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    [self.qrCodeScanningVC.view autoPinToTopLayoutGuideOfViewController:self withInset:0.0];
    [self.qrCodeScanningVC.view autoPinToSquareAspectRatio];
    // Explanation label
    UILabel *explanationLabel = [UILabel new];
    explanationLabel.text = NSLocalizedString(@"Scan the QR code of the person you'd like to securely message. They can find their QR code by going into Loki Messenger's in-app settings and clicking \"Show QR Code\".", @"");
    explanationLabel.textColor = Theme.primaryColor;
    explanationLabel.font = UIFont.ows_dynamicTypeSubheadlineClampedFont;
    explanationLabel.numberOfLines = 0;
    explanationLabel.lineBreakMode = NSLineBreakByWordWrapping;
    explanationLabel.textAlignment = NSTextAlignmentCenter;
    // Bottom view
    UIView *bottomView = [UIView new];
    [self.view addSubview:bottomView];
    [bottomView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.qrCodeScanningVC.view];
    [bottomView autoPinEdgeToSuperviewEdge:ALEdgeLeading];
    [bottomView autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    [bottomView autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [bottomView addSubview:explanationLabel];
    [explanationLabel autoPinWidthToSuperviewWithMargin:32];
    [explanationLabel autoPinHeightToSuperviewWithMargin:32];
    // Title
    self.title = NSLocalizedString(@"Scan QR Code", "");
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [UIDevice.currentDevice ows_setOrientation:UIInterfaceOrientationPortrait];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.qrCodeScanningVC startCapture];
    });
}

@end

NS_ASSUME_NONNULL_END
