#import "HttpResponse.h"
#import "Util.h"
#import "HttpRequestOrResponse.h"

@implementation HttpResponse

+(HttpResponse*) httpResponseFromStatusCode:(NSUInteger)statusCode
                              andStatusText:(NSString*)statusText
                                 andHeaders:(NSDictionary*)headers
                        andOptionalBodyText:(NSString*)optionalBody {
    
    ows_require(headers != nil);
    ows_require(statusText != nil);
    ows_require(headers != nil);
    
    HttpResponse* s = [HttpResponse new];
    s->statusCode = statusCode;
    s->statusText = statusText;
    s->headers = headers;
    s->optionalBodyText = optionalBody;
    return s;
}
+(HttpResponse*) httpResponseFromStatusCode:(NSUInteger)statusCode
                              andStatusText:(NSString*)statusText
                                 andHeaders:(NSDictionary*)headers
                        andOptionalBodyData:(NSData*)optionalBody {
    
    ows_require(headers != nil);
    ows_require(statusText != nil);
    ows_require(headers != nil);
    
    HttpResponse* s = [HttpResponse new];
    s->statusCode = statusCode;
    s->statusText = statusText;
    s->headers = headers;
    s->optionalBodyData = optionalBody;
    return s;
}
+(HttpResponse*) httpResponseFromData:(NSData*)data {
    ows_require(data != nil);
    NSUInteger responseSize;
    HttpRequestOrResponse* http = [HttpRequestOrResponse tryExtractFromPartialData:data usedLengthOut:&responseSize];
    checkOperation(http.isResponse && responseSize == data.length);
    return [http response];
}
+(HttpResponse*) httpResponse200Ok {
    return [HttpResponse httpResponse200OkWithOptionalBody:nil];
}
+(HttpResponse*) httpResponse501NotImplemented {
    return [HttpResponse httpResponseFromStatusCode:501
                                      andStatusText:@"Not Implemented"
                                         andHeaders:@{}
                                andOptionalBodyData:nil];
}
+(HttpResponse*) httpResponse500InternalServerError {
    return [HttpResponse httpResponseFromStatusCode:500
                                      andStatusText:@"Internal Server Error"
                                         andHeaders:@{}
                                andOptionalBodyData:nil];
}
+(HttpResponse*) httpResponse200OkWithOptionalBody:(NSString*)optionalBody {
    return [HttpResponse httpResponseFromStatusCode:200
                                      andStatusText:@"OK"
                                         andHeaders:@{}
                                andOptionalBodyText:optionalBody];
}
-(bool) isOkResponse {
    return statusCode == 200;
}

-(NSUInteger) getStatusCode {
    return statusCode;
}
-(NSString*) getStatusText {
    return statusText;
}

-(NSDictionary*) getHeaders {
    return headers;
}

-(bool) hasEmptyBody {
    return optionalBodyData.length == 0 && optionalBodyText.length == 0;
}
-(NSString*) getOptionalBodyText {
    if (optionalBodyText != nil) return optionalBodyText;
    if (optionalBodyData != nil) return [optionalBodyData decodedAsUtf8];
    return nil;
}
-(NSData*) getOptionalBodyData {
    if (optionalBodyData != nil) return optionalBodyData;
    if (optionalBodyText != nil) return optionalBodyText.encodedAsUtf8;
    return nil;
}

-(NSString*) toHttp {
    NSMutableArray* r = [NSMutableArray array];
    
    [r addObject:@"HTTP/1.0 "];
    [r addObject:[@(statusCode) description]];
    [r addObject:@" "];
    [r addObject:statusText];
    [r addObject:@"\r\n"];
    
    NSString* body = self.getOptionalBodyText;
    if (body != nil) {
        [r addObject:@"Content-Length: "];
        [r addObject:[@(body.length) stringValue]];
        [r addObject:@"\r\n"];
        [r addObject:body];
    } else {
        [r addObject:@"\r\n"];
    }
    
    return [r componentsJoinedByString:@""];
}
-(NSData*) serialize {
    return self.toHttp.encodedAsUtf8;
}

-(NSString*) description {
    return [NSString stringWithFormat:@"%lu %@%@",
            (unsigned long)statusCode,
            statusText,
            !self.hasBody ? @""
              : self.hasEmptyBody ? @" [empty body]"
              : @" [...body...]"];
}
-(bool) hasBody {
    return optionalBodyData != nil || optionalBodyText != nil;
}

@end
