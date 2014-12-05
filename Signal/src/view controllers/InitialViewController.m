//
//  InitialViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 19/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "InitialViewController.h"
#import "Environment.h"

@interface InitialViewController ()

@end

@implementation InitialViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSLog(@"%@",self.navigationController);

    [[Environment getCurrent]setSignUpFlowNavigationController:self.navigationController];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - Unwind segues

- (IBAction)unwindToInitial:(UIStoryboardSegue*)sender
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
