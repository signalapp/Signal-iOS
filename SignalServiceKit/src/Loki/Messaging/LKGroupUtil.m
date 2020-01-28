//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
// 

#import "LKGroupUtil.h"

@implementation LKGroupUtil

#define SignalGroupPrefix @"__textsecure_group__!"
#define MmsGroupPrefix @"__signal_mms_group__!"
#define PublicChatGroupPrefix @"__loki_public_chat_group__!"
#define RssFeedGroupPrefix @"__loki_rss_feed_group__!"

+(NSString *)getEncodedPublichChatGroupId:(NSString *)groupId
{
    return [PublicChatGroupPrefix stringByAppendingString:groupId];
}

+(NSData *)getEncodedPublichChatGroupIdAsData:(NSString *)groupId
{
    return [[PublicChatGroupPrefix stringByAppendingString:groupId] dataUsingEncoding:NSUTF8StringEncoding];
}

+(NSString *)getEncodedRssFeedGroupId:(NSString *)groupId
{
    return [RssFeedGroupPrefix stringByAppendingString:groupId];
}

+(NSData *)getEncodedRssFeedGroupIdAsData:(NSString *)groupId
{
    return [[RssFeedGroupPrefix stringByAppendingString:groupId] dataUsingEncoding:NSUTF8StringEncoding];
}

+(NSString *)getEncodedSignalGroupId:(NSString *)groupId
{
    return [SignalGroupPrefix stringByAppendingString:groupId];
}

+(NSData *)getEncodedSignalGroupIdAsData:(NSString *)groupId
{
    return [[SignalGroupPrefix stringByAppendingString:groupId] dataUsingEncoding:NSUTF8StringEncoding];
}

+(NSString *)getEncodedMmsGroupId:(NSString *)groupId
{
    return [MmsGroupPrefix stringByAppendingString:groupId];
}

+(NSData *)getEncodedMmsGroupIdAsData:(NSString *)groupId
{
    return [[MmsGroupPrefix stringByAppendingString:groupId] dataUsingEncoding:NSUTF8StringEncoding];
}

+(NSString *)getEncodedGroupId: (NSData *)groupId
{
    return [[NSString alloc]initWithData:groupId encoding:NSUTF8StringEncoding];
}

+(NSString *)getDecodedGroupId:(NSData *)groupId
{
    OWSAssertDebug(groupId.length > 0);
    NSString *encodedGroupId = [[NSString alloc]initWithData:groupId encoding:NSUTF8StringEncoding];
    if ([encodedGroupId componentsSeparatedByString:@"1"].count > 1) {
        return [encodedGroupId componentsSeparatedByString:@"!"][1];
    }
    return [encodedGroupId componentsSeparatedByString:@"!"][0];
}

+(NSData *)getDecodedGroupIdAsData:(NSData *)groupId
{
    OWSAssertDebug(groupId.length > 0);
    NSString *encodedGroupId = [[NSString alloc]initWithData:groupId encoding:NSUTF8StringEncoding];
    NSString *decodedGroupId = [encodedGroupId componentsSeparatedByString:@"!"][0];
    if ([encodedGroupId componentsSeparatedByString:@"!"].count > 1) {
        decodedGroupId =[encodedGroupId componentsSeparatedByString:@"!"][1];
    }
    return [decodedGroupId dataUsingEncoding:NSUTF8StringEncoding];
}

@end
