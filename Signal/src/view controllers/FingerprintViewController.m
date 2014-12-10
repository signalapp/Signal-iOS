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

#import "TSFingerprintGenerator.h"

@interface FingerprintViewController ()
@property TSContactThread *thread;
@end

@implementation FingerprintViewController

- (void)configWithThread:(TSThread *)thread{
    self.thread = (TSContactThread*)thread;
}


- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.view setAlpha:0];
    
    [self initializeImageViews];
    
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
    // Dispose of any resources that can be recreated.
}

#pragma mark - Initializers
- (void)initializeImageViews
{
    _contactImageView.image = [UIImage imageNamed:@"defaultConctact_light"];
    _contactImageView.layer.cornerRadius = 75.f/2;
    _contactImageView.layer.masksToBounds = YES;
    _contactImageView.layer.borderWidth = 2.0f;
    _contactImageView.layer.borderColor = [[UIColor whiteColor] CGColor];
    
    _userImageView.image = [UIImage imageNamed:@"defaultConctact_light"];
    _userImageView.layer.cornerRadius = 75.f/2;
    _userImageView.layer.masksToBounds = YES;
    _userImageView.layer.borderWidth = 2.0f;
    _userImageView.layer.borderColor = [[UIColor whiteColor] CGColor];
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

#pragma mark - Shredding & Deleting

- (void)shredAndDelete
{
    
}

@end
