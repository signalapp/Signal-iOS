
#import "NSData+Base64.h"


@implementation NSData (Base64)

+ (NSData *)dataFromBase64StringNoPadding:(NSString *)aString {
    int padding = aString.length % 4;

    NSMutableString *strResult = [aString mutableCopy];
    if (padding != 0) {
        int charsToAdd = 4 - padding;
        for (int i = 0; i < charsToAdd; i++) {
            [strResult appendString:@"="];
        }
    }
    return [self dataFromBase64String:strResult];
}

//
// dataFromBase64String:
//
// Creates an NSData object containing the base64 decoded representation of
// the base64 string 'aString'
//
// Parameters:
//    aString - the base64 string to decode
//
// returns the NSData representation of the base64 string
//

+ (NSData *)dataFromBase64String:(NSString *)aString {
    return [[NSData alloc] initWithBase64EncodedString:aString options:NSDataBase64DecodingIgnoreUnknownCharacters];
}

//
// base64EncodedString
//
// Creates an NSString object that contains the base 64 encoding of the
// receiver's data. Lines are broken at 64 characters long.
//
// returns an NSString being the base 64 representation of the
//	receiver.
//
- (NSString *)base64EncodedString {
    return [self base64EncodedStringWithOptions:0];
}

@end
