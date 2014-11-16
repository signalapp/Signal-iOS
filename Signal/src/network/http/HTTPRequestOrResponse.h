#import <Foundation/Foundation.h>
#import "HTTPRequest.h"
#import "HTTPResponse.h"

@interface HTTPRequestOrResponse : NSObject

- (instancetype)initWithRequestOrResponse:(id)requestOrResponse;
- (bool)isRequest;
- (bool)isResponse;
- (HTTPRequest*)request;
- (HTTPResponse*)response;
- (NSData*)serialize;
+ (HTTPRequestOrResponse*)tryExtractFromPartialData:(NSData*)data usedLengthOut:(NSUInteger*)usedLengthPtr;

@end
