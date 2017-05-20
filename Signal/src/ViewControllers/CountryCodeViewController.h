//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@class CountryCodeViewController;

@protocol CountryCodeViewControllerDelegate <NSObject>

- (void)countryCodeViewController:(CountryCodeViewController *)vc
             didSelectCountryCode:(NSString *)countryCode
                      countryName:(NSString *)countryName
                      callingCode:(NSString *)callingCode;

@end

#pragma mark -

@interface CountryCodeViewController : UIViewController

@property (nonatomic, weak) id<CountryCodeViewControllerDelegate> delegate;

@end
