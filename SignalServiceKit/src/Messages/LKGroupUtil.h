//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
// 

NS_ASSUME_NONNULL_BEGIN

@interface LKGroupUtil : NSObject

+(NSString *)getEncodedPublichChatGroupId:(NSString *)groupId;
+(NSData *)getEncodedPublichChatGroupIdAsData:(NSString *)groupId;

+(NSString *)getEncodedRssFeedGroupId:(NSString *)groupId;
+(NSData *)getEncodedRssFeedGroupIdAsData:(NSString *)groupId;

+(NSString *)getEncodedSignalGroupId:(NSString *)groupId;
+(NSData *)getEncodedSignalGroupIdAsData:(NSString *)groupId;

+(NSString *)getEncodedMmsGroupId:(NSString *)groupId;
+(NSData *)getEncodedMmsGroupIdAsData:(NSString *)groupId;

+(NSString *)getEncodedGroupId:(NSData *)groupId;

+(NSString *)getDecodedGroupId:(NSData *)groupId;
+(NSData *)getDecodedGroupIdAsData:(NSData *)groupId;

@end

NS_ASSUME_NONNULL_END
