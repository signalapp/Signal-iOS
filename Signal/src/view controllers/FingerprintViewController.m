//
//  FingerprintViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 02/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "FingerprintViewController.h"

#import "DJWActionSheet.h"

@interface FingerprintViewController ()

@end

@implementation FingerprintViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self initializeImageViews];
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Initializers
-(void)initializeImageViews
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
-(IBAction)closeButtonAction:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(IBAction)shredAndDelete:(id)sender
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

-(void)shredAndDelete
{
    
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
