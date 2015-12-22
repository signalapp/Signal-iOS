#import <Foundation/Foundation.h>

@interface CallFailedServerMessage : NSObject

@property (readonly, nonatomic) NSString *text;

+ (CallFailedServerMessage *)callFailedServerMessageWithText:(NSString *)text;

@end
