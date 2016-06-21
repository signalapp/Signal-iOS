#import <UIKit/UIKit.h>

#import "YapDatabase.h"
#import "YapDatabaseManualView.h"

extern NSString *ManualView_RegisteredName;
extern NSString *ManualView_GroupName;


@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (nonatomic, strong, readonly) YapDatabase *database;

@end

extern AppDelegate *TheAppDelegate;
