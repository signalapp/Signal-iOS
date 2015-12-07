//
//  TextSecureKitEnv.h
//  Pods
//
//  Created by Frederic Jacobs on 05/12/15.
//
//

#import <Foundation/Foundation.h>

#import "ContactsManagerProtocol.h"
#import "NotificationsProtocol.h"

@interface TextSecureKitEnv : NSObject

@property (nonatomic, retain) id<ContactsManagerProtocol> contactsManager;
@property (nonatomic, retain) id<NotificationsProtocol> notificationsManager;

+ (instancetype)sharedEnv;

@end