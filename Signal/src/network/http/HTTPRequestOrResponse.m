#import "HTTPRequestOrResponse.h"
#import "Constraints.h"
#import "Util.h"

@interface HTTPRequestOrResponse ()

@property (strong, nonatomic) id requestOrResponse;
@property (nonatomic) bool isRequest;

@end

@implementation HTTPRequestOrResponse

- (instancetype)initWithRequestOrResponse:(id)requestOrResponse {
    if (self = [super init]) {
        require(requestOrResponse != nil);
        self.requestOrResponse = requestOrResponse;
        require(self.isResponse || self.isRequest);
    }
    
    return self;
}

+ (HTTPRequestOrResponse*)httpRequestOrResponse:(id)requestOrResponse {
    return [[HTTPRequestOrResponse alloc] initWithRequestOrResponse:requestOrResponse];
}

- (bool)isRequest {
    return [self.requestOrResponse isKindOfClass:[HTTPRequest class]];
}

- (bool)isResponse {
    return [self.requestOrResponse isKindOfClass:[HTTPResponse class]];
}

- (HTTPRequest*)request {
    requireState(self.isRequest);
    return self.requestOrResponse;
}

- (HTTPResponse*)response {
    requireState(self.isResponse);
    return self.requestOrResponse;
}

- (NSData*)serialize {
    return [self.requestOrResponse serialize];
}

+ (instancetype)tryExtractFromPartialData:(NSData*)data usedLengthOut:(NSUInteger*)usedLengthPtr {
    require(data != nil);

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
        NSString* headerValue = [[headerLine substringFromIndex:[(NSString*)headerLineParts[0] length]+1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
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
        HTTPResponse* response = [[HTTPResponse alloc] initFromStatusCode:statusCode
                                                            andStatusText:statusText
                                                               andHeaders:headers
                                                      andOptionalBodyData:optionalBodyData];
        return [[HTTPRequestOrResponse alloc] initWithRequestOrResponse:response];
    } else {
        checkOperation(requestOrResponseLineParts.count == 3);
        NSString* method = requestOrResponseLineParts[0];
        NSString* location = requestOrResponseLineParts[1];
        HTTPRequest* request = [[HTTPRequest alloc] initWithMethod:method
                                                       andLocation:location
                                                        andHeaders:headers
                                                   andOptionalBody:[optionalBodyData decodedAsUtf8]];
        return [[HTTPRequestOrResponse alloc] initWithRequestOrResponse:request];
    }
}

- (NSString*)description {
    return [self.requestOrResponse description];
}

@end
