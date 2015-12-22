//
//  APNavigationController.m
//  DropDownToolBar
//
//  Created by Ankur Patel on 2/24/14.
//  Copyright (c) 2014 Encore Dev Labs LLC. All rights reserved.
//

#import "APNavigationController.h"

@interface APNavigationController ()

@property (nonatomic, copy) NSString *originalNavigationBarTitle;
@property (nonatomic, copy) NSString *originalBarButtonTitle;

@end

@implementation APNavigationController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.dropDownToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 64)];
    self.dropDownToolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.dropDownToolbar.tintColor        = self.navigationBar.tintColor;
    [self.navigationBar.superview insertSubview:self.dropDownToolbar belowSubview:self.navigationBar];
    self.originalNavigationBarTitle = self.navigationBar.topItem.title;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)toggleDropDown:(id)sender {
    if (self.isDropDownVisible) {
        [self hideDropDown:sender];
    } else {
        [self showDropDown:sender];
    }
}

- (void)hideDropDown:(id)sender {
    if (self.isDropDownVisible) {
        __weak APNavigationController *weakSelf = self;
        CGRect frame                            = self.dropDownToolbar.frame;
        frame.origin.y                          = CGRectGetMaxY(self.navigationBar.frame);
        self.dropDownToolbar.frame              = frame;
        [UIView animateWithDuration:0.25
            animations:^{
              CGRect finalframe              = self.dropDownToolbar.frame;
              finalframe.origin.y            = 0.;
              weakSelf.dropDownToolbar.frame = finalframe;
            }
            completion:^(BOOL finished) {
              weakSelf.isDropDownVisible      = !weakSelf.isDropDownVisible;
              weakSelf.dropDownToolbar.hidden = YES;
            }];
        if (self.activeNavigationBarTitle) {
            self.navigationBar.topItem.title = self.originalNavigationBarTitle;
        }
        if (sender && [sender isKindOfClass:[UIBarButtonItem class]]) {
            [(UIBarButtonItem *)sender setTitle:self.originalBarButtonTitle];
        }
    }
}

- (void)showDropDown:(id)sender {
    if (!self.isDropDownVisible) {
        __weak APNavigationController *weakSelf = self;
        CGRect frame                            = self.dropDownToolbar.frame;
        frame.origin.y                          = 0.f;
        self.dropDownToolbar.hidden             = NO;
        self.dropDownToolbar.frame              = frame;
        [UIView animateWithDuration:0.25
            animations:^{
              CGRect finalframe              = self.dropDownToolbar.frame;
              finalframe.origin.y            = CGRectGetMaxY(self.navigationBar.frame);
              weakSelf.dropDownToolbar.frame = finalframe;
            }
            completion:^(BOOL finished) {
              weakSelf.isDropDownVisible = !weakSelf.isDropDownVisible;
            }];
        if (self.activeNavigationBarTitle) {
            self.navigationBar.topItem.title = self.activeNavigationBarTitle;
        }
        if (sender && [sender isKindOfClass:[UIBarButtonItem class]]) {
            self.originalBarButtonTitle = [(UIBarButtonItem *)sender title];
            if (self.activeBarButtonTitle) {
                [(UIBarButtonItem *)sender setTitle:self.activeBarButtonTitle];
            }
        }
    }
}

@end
