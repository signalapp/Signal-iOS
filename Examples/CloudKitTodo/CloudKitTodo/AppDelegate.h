#import <UIKit/UIKit.h>
#import <Reachability/Reachability.h>

#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseCloudKit.h>

@class AppDelegate;
extern AppDelegate *MyAppDelegate;


@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;

@property (nonatomic, strong, readonly) Reachability *reachability;

@end
