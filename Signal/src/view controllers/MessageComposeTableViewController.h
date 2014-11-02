//
//  MessageComposeTableViewController.h
//  
//
//  Created by Dylan Bourgeois on 02/11/14.
//
//

#import <UIKit/UIKit.h>

#import "DemoDataFactory.h"
#import "Contact.h"

@interface MessageComposeTableViewController : UITableViewController <UISearchBarDelegate>

@property (nonatomic, strong) IBOutlet UISearchBar * searchBar;

@end
