//
//  ScanIdentityBarcodeViewController.m
//  Signal-iOS
//
//  Created by Christine Corbett Moran on 3/29/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//


#import "ScanIdentityBarcodeViewController.h"
#import "NSData+Base64.h"

@implementation ScanIdentityBarcodeViewController

- (void)didDetectQRCodeWithString:(NSString *)string
{
    NSData *data = [NSData dataFromBase64String:string];
    NSString *dialogTitle;
    NSString *dialogDescription;

    if ([data isEqualToData:self.identityKey]) {
        dialogTitle = NSLocalizedString(@"SCAN_KEY_VERIFIED_TITLE", @"");
        dialogDescription = NSLocalizedString(@"SCAN_KEY_VERIFIED_TEXT", @"");
    } else {
        dialogTitle = NSLocalizedString(@"SCAN_KEY_CONFLICT_TITLE", @"");
        dialogDescription = NSLocalizedString(@"SCAN_KEY_CONFLICT_TEXT", @"");
    }

    UIAlertController *controller = [UIAlertController alertControllerWithTitle:dialogTitle
                                                                        message:dialogDescription
                                                                 preferredStyle:UIAlertControllerStyleAlert];
    [self
        presentViewController:controller
                     animated:YES
                   completion:^{
                       [self performSelector:@selector(dismissScannerAfterSuccesfullScan) withObject:nil afterDelay:5];
                   }];
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
