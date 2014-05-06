#import <Foundation/Foundation.h>

/**
 *
 * ShortAuthenticationStringGenerator is utility class responsible for generating the Short Authentication String.
 * Speaking the SAS is used to detect man-in-the-middle attacks.
 *
**/

@interface ShortAuthenticationStringGenerator : NSObject

+(NSString*)generateFromData:(NSData*)sasBytes;

@end
