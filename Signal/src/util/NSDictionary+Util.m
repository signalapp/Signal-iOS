#import "NSData+Util.h"
#import "NSDictionary+Util.h"
#import "Constraints.h"

@implementation NSDictionary (Util)

- (NSString*)encodedAsJSON {
    NSError* jsonSerializeError = nil;
    NSData* data = [NSJSONSerialization dataWithJSONObject:self
                                                   options:0
                                                     error:&jsonSerializeError];
    checkOperation(jsonSerializeError == nil);
    return [data decodedAsUtf8];
}

@end
