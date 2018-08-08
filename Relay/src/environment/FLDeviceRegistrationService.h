//
//  FLDeviceRegistrationService.h
//  Forsta
//
//  Created by Mark Descalzo on 1/31/18.
//  Copyright © 2018 Forsta. All rights reserved.
//

//#import <SocketRocket/SocketRocket.h>

extern NSString *const FLRegistrationStatusUpdateNotification;
//#define FLRegistrationStatusUpdateNotification @"FLRegistrationStatusUpdateNotification"

@import Foundation;

@interface FLDeviceRegistrationService : NSObject

+(instancetype _Nonnull)sharedInstance;

-(void)registerWithTSSWithCompletion:(void (^_Nullable)(NSError * _Nullable error))completionBlock;
-(void)provisionOtherDeviceWithPublicKey:(NSString *_Nonnull)keyString andUUID:(NSString *_Nonnull)uuidString;

// This will de-register all other devices associated with this account.  Use carefully.
-(void)forceRegistrationWithCompletion:(void (^_Nullable)(NSError * _Nullable error))completionBlock;


@end
