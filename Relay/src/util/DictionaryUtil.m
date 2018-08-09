#import "Constraints.h"
#import "DataUtil.h"
#import "DictionaryUtil.h"

@implementation NSDictionary (Util)

- (NSString *)encodedAsJson {
    NSError *jsonSerializeError = nil;
    NSData *data                = [NSJSONSerialization dataWithJSONObject:self options:0 error:&jsonSerializeError];
    checkOperation(jsonSerializeError == nil);
    return [data decodedAsUtf8];
}

@end
