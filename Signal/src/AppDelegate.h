#import <UIKit/UIKit.h>
#import "FutureSource.h"

#pragma mark Logging - Production logging wants us to write some logs to a file in case we need it for debugging.

#import <CocoaLumberjack/DDTTYLogger.h>
#import <CocoaLumberjack/DDFileLogger.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate> 

@property (strong, nonatomic) UIWindow *window;
@property (nonatomic, readonly) DDFileLogger *fileLogger;

@end
