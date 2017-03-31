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

@interface CountryCodeViewController
    : UIViewController <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate, UISearchDisplayDelegate>

@property (nonatomic) IBOutlet UITableView *countryCodeTableView;
@property (nonatomic) IBOutlet UISearchBar *searchBar;
@property (nonatomic, weak) id<CountryCodeViewControllerDelegate> delegate;
@property (nonatomic) NSString *countryCodeSelected;
@property (nonatomic) NSString *callingCodeSelected;
@property (nonatomic) NSString *countryNameSelected;

@end
