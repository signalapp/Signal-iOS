//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSTableViewController.h"

@class CountryCodeViewController;

@protocol CountryCodeViewControllerDelegate <NSObject>

- (void)countryCodeViewController:(CountryCodeViewController *)vc
             didSelectCountryCode:(NSString *)countryCode
                      countryName:(NSString *)countryName
                      callingCode:(NSString *)callingCode;

@end

#pragma mark -

@interface CountryCodeViewController : OWSTableViewController

@property (nonatomic, weak) id<CountryCodeViewControllerDelegate> countryCodeDelegate;

@property (nonatomic) BOOL isPresentedInNavigationController;

@property (nonatomic) UIInterfaceOrientationMask interfaceOrientationMask;

@end
