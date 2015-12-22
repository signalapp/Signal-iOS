#import "HttpRequestOrResponse.h"
#import "Constraints.h"
#import "Util.h"

@implementation HttpRequestOrResponse

+(HttpRequestOrResponse*) httpRequestOrResponse:(id)requestOrResponse {
    ows_require(requestOrResponse != nil);
    
    HttpRequestOrResponse* h = [HttpRequestOrResponse new];
    h->requestOrResponse = requestOrResponse;
    ows_require(h.isResponse || h.isRequest);
    return h;
}
-(bool) isRequest {
    return [requestOrResponse isKindOfClass:HttpRequest.class];
}
-(bool) isResponse {
    return [requestOrResponse isKindOfClass:HttpResponse.class];
}
-(HttpRequest*) request {
    requireState(self.isRequest);
    return requestOrResponse;
}
-(HttpResponse*) response {
    requireState(self.isResponse);
    return requestOrResponse;
}
-(NSData*) serialize {
    return [requestOrResponse serialize];
}

+(HttpRequestOrResponse*) tryExtractFromPartialData:(NSData*)data usedLengthOut:(NSUInteger*)usedLengthPtr {
    ows_require(data != nil);

    // first line should contain HTTP
    checkOperation([data tryFindIndexOf:@"\r\n".encodedAsAscii] == nil || [data tryFindIndexOf:@"HTTP".encodedAsAscii] != nil);
    // expecting \r\n line endings
    checkOperation(([data tryFindIndexOf:@"\n".encodedAsAscii] == nil) == ([data tryFindIndexOf:@"\r\n".encodedAsAscii] == nil));
    
    NSNumber* tryHeaderLength = [data tryFindIndexOf:@"\r\n\r\n".encodedAsUtf8];
    if (tryHeaderLength == nil) return nil;
    NSUInteger headerLength = [tryHeaderLength unsignedIntegerValue];
    NSString* fullHeader = [[data take:headerLength] decodedAsUtf8];
    headerLength += 4; // account for \r\n\r\n
    
    NSArray* headerLines = [fullHeader componentsSeparatedByString:@"\r\n"];
    checkOperation(headerLines.count >= 1);
    
    //      GET /index.html HTTP/1.1
    //      HTTP/1.1 200 OK
    NSString* requestOrResponseLine = headerLines[0];
    NSArray* requestOrResponseLineParts = [requestOrResponseLine componentsSeparatedByString:@" "];
    checkOperation(requestOrResponseLineParts.count >= 3);
    bool isResponse = [requestOrResponseLineParts[0] hasPrefix:@"HTTP/"];
    
    //      Host: www.example.com
    //      Content-Length: 5
    NSMutableDictionary* headers = [NSMutableDictionary dictionary];
    for (NSUInteger i = 1; i < headerLines.count; i++) {
        NSString* headerLine = headerLines[i];
        
        NSArray* headerLineParts = [headerLine componentsSeparatedByString:@":"];
        checkOperation(headerLineParts.count >= 2);
        NSString* headerKey = [headerLineParts[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString* headerValue = [[headerLine substringFromIndex:[(NSString *)headerLineParts[0] length]+1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        headers[headerKey] = headerValue;
    }
    
    NSString* contextLengthText = headers[@"Content-Length"];
    NSNumber* contentLengthParsed = [contextLengthText tryParseAsUnsignedInteger];
    checkOperation((contextLengthText == nil) == (contentLengthParsed == nil));
    
    bool hasContent = contentLengthParsed != nil;
    NSUInteger contentLength = [contentLengthParsed unsignedIntegerValue];
    if (headerLength + contentLength > data.length) return nil; // need more data
    NSData* optionalBodyData = hasContent ? [data subdataWithRange:NSMakeRange(headerLength, contentLength)] : nil;
    
    *usedLengthPtr = headerLength + contentLength;
    if (isResponse) {
        NSNumber* statusCodeParsed = [requestOrResponseLineParts[1] tryParseAsUnsignedInteger];
        checkOperation(statusCodeParsed != nil);
        
        NSUInteger statusCode = [statusCodeParsed unsignedIntegerValue];
        NSString* statusText = [[requestOrResponseLineParts subarrayWithRange:NSMakeRange(2, requestOrResponseLineParts.count - 2)] componentsJoinedByString:@" "];
        HttpResponse* response = [HttpResponse httpResponseFromStatusCode:statusCode
                                                            andStatusText:statusText
                                                               andHeaders:headers
                                                      andOptionalBodyData:optionalBodyData];
        return [HttpRequestOrResponse httpRequestOrResponse:response];
    } else {
        checkOperation(requestOrResponseLineParts.count == 3);
        NSString* method = requestOrResponseLineParts[0];
        NSString* location = requestOrResponseLineParts[1];
        HttpRequest* request = [HttpRequest httpRequestWithMethod:method
                                                      andLocation:location
                                                       andHeaders:headers
                                                  andOptionalBody:[optionalBodyData decodedAsUtf8]];
        return [HttpRequestOrResponse httpRequestOrResponse:request];
    }
}

-(NSString*) description {
    return [requestOrResponse description];
}

@end
