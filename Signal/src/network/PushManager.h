#import <Foundation/Foundation.h>
#import "CollapsingFutures.h"

/**
 *
 * The push manager is used to trigger (and react to) registration of push notifications.
 *
 */
@interface PushManager : NSObject

+(instancetype)sharedManager;

-(void)verifyPushActivated;

-(TOCFuture*)askForPushRegistration;

-(void)didRegisterForPushNotificationsToDevice:(NSData*)deviceToken;

-(void)didFailToRegisterForPushNotificationsWithError:(NSError*)error;

@end

