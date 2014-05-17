#import <UIKit/UIKit.h>

#import "YapDatabase.h"
#import "YapDatabaseView.h"
#import "YapDatabaseFullTextSearch.h"
#import "YapDatabaseSearchResultsView.h"


@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;

@property (nonatomic, strong, readonly) YapDatabase *database;

@end

extern AppDelegate *TheAppDelegate;
