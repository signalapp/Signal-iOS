//
//  FingerprintViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 02/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "FingerprintViewController.h"

#import "Cryptography.h"
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <25519/Curve25519.h>
#import "NSData+hexString.h"
#import "DJWActionSheet.h"
#import "TSStorageManager.h"
#import "TSStorageManager+IdentityKeyStore.h"
#import "PresentIdentityQRCodeViewController.h"
#import "ScanIdentityBarcodeViewController.h"
#include "NSData+Base64.h"

#import "TSFingerprintGenerator.h"

@interface FingerprintViewController ()
@property TSContactThread *thread;
@property BOOL didShowInfo;
@end

@implementation FingerprintViewController

- (void)configWithThread:(TSThread *)thread{
    self.thread = (TSContactThread*)thread;
}


- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.view setAlpha:0];
    
    [self hideInfo];
    
}

- (void)viewWillAppear:(BOOL)animated
{
    self.contactFingerprintTitleLabel.text = self.thread.name;
    NSData *identityKey = [[TSStorageManager sharedManager] identityKeyForRecipientId:self.thread.contactIdentifier];
    self.contactFingerprintLabel.text = [TSFingerprintGenerator getFingerprintForDisplay:identityKey];
    
    NSData *myPublicKey = [[TSStorageManager sharedManager] identityKeyPair].publicKey;
    self.userFingerprintLabel.text = [TSFingerprintGenerator getFingerprintForDisplay:myPublicKey];
    
    [UIView animateWithDuration:0.6 delay:0. options:UIViewAnimationOptionCurveEaseInOut animations:^{
        [self.view setAlpha:1];
    } completion:nil];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

-(NSData*) getMyPublicIdentityKey {
    return [[TSStorageManager sharedManager] identityKeyPair].publicKey;
}

-(NSData*) getTheirPublicIdentityKey {
    return [[TSStorageManager sharedManager] identityKeyForRecipientId:self.thread.contactIdentifier];
    
}

-(void)showInfo
{
    _didShowInfo = YES;
    
    _infoArrowTop.hidden         = NO;
    _infoArrowBottom.hidden      = NO;
    _infoMyFingerprint.hidden    = NO;
    _infoTheirFingerprint.hidden = NO;
    
    [UIView animateWithDuration:0.3f delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^(){
        _infoArrowTop.alpha         = 1;
        _infoArrowBottom.alpha      = 1;
        _infoMyFingerprint.alpha    = 1;
        _infoTheirFingerprint.alpha = 1;
        _presentationLabel.alpha    = 0;
    } completion:nil];
    
    _presentationLabel.hidden    = YES;

}

-(void)hideInfo
{
    
    _didShowInfo = NO;
    _presentationLabel.hidden    = NO;

    [UIView animateWithDuration:0.3f delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^(){
        _infoArrowTop.alpha         = 0;
        _infoArrowBottom.alpha      = 0;
        _infoMyFingerprint.alpha    = 0;
        _infoTheirFingerprint.alpha = 0;
        _presentationLabel.alpha    = 1;
    } completion:^(BOOL done){
        
        if (done) {
            _infoArrowTop.hidden         = YES;
            _infoArrowBottom.hidden      = YES;
            _infoMyFingerprint.hidden    = YES;
            _infoTheirFingerprint.hidden = YES;
        }

    }];
    

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

- (IBAction)showInfoAction:(id)sender
{
    if (!_didShowInfo) {
        [self showInfo];
    } else {
        [self hideInfo];
    }
}

- (IBAction)shredAndDelete:(id)sender
{
    [DJWActionSheet showInView:self.view withTitle:@"Are you sure wou want to shred all communications with this contact ? This action is irreversible."
             cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@[@"Shred all communications & delete contact"]
                      tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                          if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                              NSLog(@"User Cancelled");
                          } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex) {
                              NSLog(@"Destructive button tapped");
                          }else {
                              [self shredAndDelete];
                          }
                      }];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if([[segue identifier] isEqualToString:@"PresentIdentityQRCodeViewSegue"]){
        [segue.destinationViewController setIdentityKey:[[self getMyPublicIdentityKey] prependKeyType]];
    }
    else if([[segue identifier] isEqualToString:@"ScanIdentityBarcodeViewSegue"]){
        [segue.destinationViewController setIdentityKey:[[self getTheirPublicIdentityKey] prependKeyType]];
    }
    
}


- (IBAction)unwindToIdentityKeyWasVerified:(UIStoryboardSegue *)segue{
    // Can later be used to mark identity key as verified if we want step above TOFU in UX
}


- (IBAction)unwindCancel:(UIStoryboardSegue *)segue{
    NSLog(@"action cancelled");
    // Can later be used to mark identity key as verified if we want step above TOFU in UX
}

#pragma mark - Shredding & Deleting

- (void)shredAndDelete {
#warning unimplemented: shredAndDelete
}

@end
