#import "LKGroupUtilities.h"

@implementation LKGroupUtilities

#define ClosedGroupPrefix @"__textsecure_group__!"
#define MMSGroupPrefix @"__signal_mms_group__!"
#define OpenGroupPrefix @"__loki_public_chat_group__!"

+(NSString *)getEncodedOpenGroupID:(NSString *)groupID
{
    return [OpenGroupPrefix stringByAppendingString:groupID];
}

+(NSData *)getEncodedOpenGroupIDAsData:(NSString *)groupID
{
    return [[OpenGroupPrefix stringByAppendingString:groupID] dataUsingEncoding:NSUTF8StringEncoding];
}

+(NSString *)getEncodedClosedGroupID:(NSString *)groupID
{
    return [ClosedGroupPrefix stringByAppendingString:groupID];
}

+(NSData *)getEncodedClosedGroupIDAsData:(NSString *)groupID
{
    return [[ClosedGroupPrefix stringByAppendingString:groupID] dataUsingEncoding:NSUTF8StringEncoding];
}

+(NSString *)getEncodedMMSGroupID:(NSString *)groupID
{
    return [MMSGroupPrefix stringByAppendingString:groupID];
}

+(NSData *)getEncodedMMSGroupIDAsData:(NSString *)groupID
{
    return [[MMSGroupPrefix stringByAppendingString:groupID] dataUsingEncoding:NSUTF8StringEncoding];
}

+(NSString *)getEncodedGroupID:(NSData *)groupID
{
    return [[NSString alloc] initWithData:groupID encoding:NSUTF8StringEncoding];
}

+(NSString *)getDecodedGroupID:(NSData *)groupID
{
    NSString *encodedGroupID = [[NSString alloc] initWithData:groupID encoding:NSUTF8StringEncoding];
    if ([encodedGroupID componentsSeparatedByString:@"!"].count > 1) {
        return [encodedGroupID componentsSeparatedByString:@"!"][1];
    }
    return [encodedGroupID componentsSeparatedByString:@"!"][0];
}

+(NSData *)getDecodedGroupIDAsData:(NSData *)groupID
{
    return [[LKGroupUtilities getDecodedGroupID:groupID] dataUsingEncoding:NSUTF8StringEncoding];
}

@end
