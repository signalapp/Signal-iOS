#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class CloudKitManager;

/**
 * You can use this as an alternative to the sharedInstance:
 * [[CloudKitManager sharedInstance] foobar] -> MyCloudKitManager.foobar
**/
extern CloudKitManager *MyCloudKitManager;


@interface CloudKitManager : NSObject

/**
 * Standard singleton pattern.
 * As a shortcut, you can use the global MyCloudKitManager ivar instead.
**/
+ (instancetype)sharedInstance; // Or MyCloudKitManager global ivar

/**
 * This method uses CKFetchRecordChangesOperation to fetch changes.
 * It continues fetching until its reported that we're caught up.
 * 
 * This method is invoked once automatically, when the CloudKitManager is initialized.
 * After that, one should invoke it anytime a corresponding push notification is received.
**/
- (void)fetchRecordChangesWithCompletionHandler:
                            (void (^)(UIBackgroundFetchResult result, BOOL moreComing))completionHandler;

@end
