//
//  APNavigationController.h
//  DropDownToolBar
//
//  Created by Ankur Patel on 2/24/14.
//  Copyright (c) 2014 Encore Dev Labs LLC. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface APNavigationController : UINavigationController

@property (nonatomic, strong)
    UIToolbar *dropDownToolbar; // Reference to dynamically change items based on which bar button item is clicked
@property (nonatomic, strong) NSString *activeNavigationBarTitle; // Navigation bar title when the toolbar is shown
@property (nonatomic, strong) NSString *activeBarButtonTitle;     // UIBarButton title when toolbar is shown
@property (nonatomic, assign) BOOL isDropDownVisible;

- (void)setActiveBarButtonTitle:(NSString *)title;
- (void)setActiveNavigationBarTitle:(NSString *)title;
- (void)toggleDropDown:(id)sender;
- (void)hideDropDown:(id)sender;
- (void)showDropDown:(id)sender;

@end
