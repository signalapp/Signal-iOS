#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LKGroupUtilities : NSObject

+(NSString *)getEncodedOpenGroupID:(NSString *)groupID;
+(NSData *)getEncodedOpenGroupIDAsData:(NSString *)groupID;

+(NSString *)getEncodedClosedGroupID:(NSString *)groupID;
+(NSData *)getEncodedClosedGroupIDAsData:(NSString *)groupID;

+(NSString *)getEncodedMMSGroupID:(NSString *)groupID;
+(NSData *)getEncodedMMSGroupIDAsData:(NSString *)groupID;

+(NSString *)getEncodedGroupID:(NSData *)groupID;

+(NSString *)getDecodedGroupID:(NSData *)groupID;
+(NSData *)getDecodedGroupIDAsData:(NSData *)groupID;

@end

NS_ASSUME_NONNULL_END
