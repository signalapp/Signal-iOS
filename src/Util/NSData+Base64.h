#import <Foundation/Foundation.h>

@interface NSData (Base64)

+ (NSData *)dataFromBase64StringNoPadding:(NSString *)aString;
+ (NSData *)dataFromBase64String:(NSString *)aString;

- (NSString *)base64EncodedString;

@end
