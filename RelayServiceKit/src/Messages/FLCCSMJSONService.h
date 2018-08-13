//
//  FLCCSMJSONService.h
//  Forsta
//
//  Created by Mark on 6/15/17.
//  Copyright © 2017 Forsta. All rights reserved.
//

#import <Foundation/Foundation.h>

@class TSMessage;

@interface FLCCSMJSONService : NSObject

+(NSString *_Nullable)blobFromMessage:(TSMessage *_Nonnull)message;
+(nullable NSArray *)arrayFromMessageBody:(NSString *_Nonnull)body;
+(nullable NSDictionary *)payloadDictionaryFromMessageBody:(NSString *_Nullable)body;

@end
