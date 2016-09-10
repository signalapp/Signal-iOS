//
//  ScanIdentityBarcodeViewController.h
//  Signal-iOS
//
//  Created by Christine Corbett Moran on 3/29/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "OWSQRCodeScanningViewController.h"

@interface ScanIdentityBarcodeViewController : OWSQRCodeScanningViewController

@property (nonatomic, strong) NSData *identityKey;

@end
