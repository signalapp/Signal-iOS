#import <Foundation/Foundation.h>
#import "HTTPRequest.h"
#import "HTTPResponse.h"

@interface HTTPRequestOrResponse : NSObject

- (instancetype)initWithRequestOrResponse:(id)requestOrResponse;
+ (instancetype)tryExtractFromPartialData:(NSData*)data usedLengthOut:(NSUInteger*)usedLengthPtr;

- (bool)isRequest;
- (bool)isResponse;
- (HTTPRequest*)request;
- (HTTPResponse*)response;
- (NSData*)serialize;

@end
