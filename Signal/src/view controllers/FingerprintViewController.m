//
//  FingerprintViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 02/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "FingerprintViewController.h"

@interface FingerprintViewController ()

@end

@implementation FingerprintViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Action
-(IBAction)closeButtonAction:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(IBAction)infoButtonAction:(id)sender {
    //Present an infographic about fingerprints and how to verify contact's identity
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
