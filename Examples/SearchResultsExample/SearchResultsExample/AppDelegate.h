#import <UIKit/UIKit.h>

#import "YapDatabase.h"
#import "YapDatabaseAutoView.h"
#import "YapDatabaseFullTextSearch.h"
#import "YapDatabaseSearchResultsView.h"


@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (nonatomic, strong, readonly) YapDatabase *database;

@end

extern AppDelegate *TheAppDelegate;
