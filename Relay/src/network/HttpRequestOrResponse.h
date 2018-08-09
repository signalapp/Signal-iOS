#import <Foundation/Foundation.h>
#import "HttpRequest.h"
#import "HttpResponse.h"

@interface HttpRequestOrResponse : NSObject {
@private id requestOrResponse;
@private bool isRequest;
}

+(HttpRequestOrResponse*) httpRequestOrResponse:(id)requestOrResponse;
-(bool) isRequest;
-(bool) isResponse;
-(HttpRequest*) request;
-(HttpResponse*) response;
-(NSData*) serialize;
+(HttpRequestOrResponse*) tryExtractFromPartialData:(NSData*)data usedLengthOut:(NSUInteger*)usedLengthPtr;

@end
