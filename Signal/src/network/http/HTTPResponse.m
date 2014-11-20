#import "HTTPResponse.h"
#import "Util.h"
#import "Constraints.h"
#import "HTTPRequestOrResponse.h"

@interface HTTPResponse ()

@property (nonatomic, readwrite, getter=getStatusCode)               NSUInteger    statusCode;
@property (strong, nonatomic, readwrite, getter=getStatusText)       NSString*     statusText;
@property (strong, nonatomic, readwrite, getter=getHeaders)          NSDictionary* headers;
@property (strong, nonatomic, readwrite, getter=getOptionalBodyText) NSString*     optionalBodyText;
@property (strong, nonatomic, readwrite, getter=getOptionalBodyData) NSData*       optionalBodyData;

@end

@implementation HTTPResponse

- (instancetype)initFromStatusCode:(NSUInteger)statusCode
                     andStatusText:(NSString*)statusText
                        andHeaders:(NSDictionary*)headers
               andOptionalBodyText:(NSString*)optionalBody {
    self = [super init];
	
    if (self) {
        require(headers != nil);
        require(statusText != nil);
        require(headers != nil);
        
        self.statusCode = statusCode;
        self.statusText = statusText;
        self.headers = headers;
        self.optionalBodyText = optionalBody;
    }
    
    return self;
}

- (instancetype)initFromStatusCode:(NSUInteger)statusCode
                     andStatusText:(NSString*)statusText
                        andHeaders:(NSDictionary*)headers
               andOptionalBodyData:(NSData*)optionalBody {
    self = [super init];
	
    if (self) {
        require(headers != nil);
        require(statusText != nil);
        require(headers != nil);
        
        self.statusCode = statusCode;
        self.statusText = statusText;
        self.headers = headers;
        self.optionalBodyData = optionalBody;
    }
    
    return self;
}

+ (instancetype)httpResponseFromData:(NSData*)data {
    require(data != nil);
    NSUInteger responseSize;
    HTTPRequestOrResponse* http = [HTTPRequestOrResponse tryExtractFromPartialData:data usedLengthOut:&responseSize];
    checkOperation(http.isResponse && responseSize == data.length);
    return [http response];
}

+ (instancetype)httpResponse200Ok {
    return [HTTPResponse httpResponse200OkWithOptionalBody:nil];
}

+ (instancetype)httpResponse501NotImplemented {
    return [[HTTPResponse alloc] initFromStatusCode:501
                                      andStatusText:@"Not Implemented"
                                         andHeaders:@{}
                                andOptionalBodyData:nil];
}

+ (instancetype)httpResponse500InternalServerError {
    return [[HTTPResponse alloc] initFromStatusCode:500
                                      andStatusText:@"Internal Server Error"
                                         andHeaders:@{}
                                andOptionalBodyData:nil];
}

+ (instancetype)httpResponse200OkWithOptionalBody:(NSString*)optionalBody {
    return [[HTTPResponse alloc] initFromStatusCode:200
                                      andStatusText:@"OK"
                                         andHeaders:@{}
                                andOptionalBodyText:optionalBody];
}

- (bool)isOkResponse {
    return self.statusCode == 200;
}

- (bool)hasEmptyBody {
    return self.optionalBodyData.length == 0 && self.optionalBodyText.length == 0;
}

//@synthesize optionalBodyText = _optionalBodyText;

- (void)setOptionalBodyText:(NSString*)optionalBodyText {
    if (optionalBodyText) {
        _optionalBodyText = optionalBodyText;
        if (!self.optionalBodyData) {
            self.optionalBodyData = [optionalBodyText encodedAsUtf8];
        }
    }
}

- (void)setOptionalBodyData:(NSData*)optionalBodyData {
    if (optionalBodyData) {
        _optionalBodyData = optionalBodyData;
        if (!self.optionalBodyText) {
            self.optionalBodyText = [optionalBodyData decodedAsUtf8];
        }
    }
}

- (NSString*)toHTTP {
    NSMutableArray* r = [[NSMutableArray alloc] init];
    
    [r addObject:@"HTTP/1.0 "];
    [r addObject:[@(self.statusCode) description]];
    [r addObject:@" "];
    [r addObject:self.statusText];
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

- (NSData*)serialize {
    return self.toHTTP.encodedAsUtf8;
}

- (NSString*)description {
    return [NSString stringWithFormat:@"%lu %@%@",
            (unsigned long)self.statusCode,
            self.statusText,
            !self.hasBody ? @""
              : self.hasEmptyBody ? @" [empty body]"
              : @" [...body...]"];
}

- (bool)hasBody {
    return self.optionalBodyData != nil || self.optionalBodyText != nil;
}

@end
