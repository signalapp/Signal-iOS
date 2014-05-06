//
//  KeyChainStorage.h
//  Signal
//
//  Created by Frederic Jacobs on 06/05/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
@class PhoneNumber, Zid;
@interface KeyChainStorage : NSObject

+(PhoneNumber*) forceGetLocalNumber;
+(PhoneNumber*)tryGetLocalNumber;
+(void) setLocalNumberTo:(PhoneNumber*)localNumber;
+(Zid*) getOrGenerateZid;
+(NSString*) getOrGenerateSavedPassword;
+(NSData*) getOrGenerateSignalingMacKey;
+(NSData*) getOrGenerateSignalingCipherKey;
+(NSData*) getOrGenerateSignalingExtraKey;

+ (void)clear;

@end
