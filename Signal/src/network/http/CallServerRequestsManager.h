#import <Foundation/Foundation.h>
#import <AFNetworking/AFNetworking.h>
#import "CollapsingFutures.h"

@interface CallServerRequestsManager : NSObject

MacrosSingletonInterface

-(TOCFuture*)asyncRequestPushNotificationToDevice:(NSData*)deviceToken;

@end
