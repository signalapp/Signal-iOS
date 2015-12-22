#import "CryptoTools.h"
#import "HttpRequest.h"
#import "HttpRequestOrResponse.h"
#import "Util.h"

@interface HttpRequest ()
@property NSString *method;
@property NSString *location;
@property NSString *optionalBody;
@property NSDictionary *headers;

@end

@implementation HttpRequest

+ (HttpRequest *)httpRequestWithMethod:(NSString *)method
                           andLocation:(NSString *)location
                            andHeaders:(NSDictionary *)headers
                       andOptionalBody:(NSString *)optionalBody {
    ows_require(method != nil);
    ows_require(location != nil);
    ows_require(headers != nil);
    ows_require((optionalBody == nil) == (headers[@"Content-Length"] == nil));
    ows_require(optionalBody == nil || [[@(optionalBody.length) description] isEqualToString:headers[@"Content-Length"]]);

    HttpRequest *s   = [HttpRequest new];
    s->_method       = method;
    s->_location     = location;
    s->_optionalBody = optionalBody;
    s->_headers      = headers;
    return s;
}
+ (HttpRequest *)httpRequestUnauthenticatedWithMethod:(NSString *)method
                                          andLocation:(NSString *)location
                                      andOptionalBody:(NSString *)optionalBody {
    ows_require(method != nil);
    ows_require(location != nil);

    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    if (optionalBody != nil) {
        headers[@"Content-Length"] = [@(optionalBody.length) stringValue];
    }

    HttpRequest *s   = [HttpRequest new];
    s->_method       = method;
    s->_location     = location;
    s->_optionalBody = optionalBody;
    s->_headers      = headers;
    return s;
}
+ (HttpRequest *)httpRequestWithBasicAuthenticationAndMethod:(NSString *)method
                                                 andLocation:(NSString *)location
                                             andOptionalBody:(NSString *)optionalBody
                                              andLocalNumber:(NSString *)localNumber
                                                 andPassword:(NSString *)password {
    ows_require(method != nil);
    ows_require(location != nil);
    ows_require(password != nil);
    ows_require(localNumber != nil);

    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    if (optionalBody != nil) {
        headers[@"Content-Length"] = [@(optionalBody.length) stringValue];
    }
    headers[@"Authorization"] =
        [HttpRequest computeBasicAuthorizationTokenForLocalNumber:localNumber andPassword:password];

    HttpRequest *s   = [HttpRequest new];
    s->_method       = method;
    s->_location     = location;
    s->_optionalBody = optionalBody;
    s->_headers      = headers;
    return s;
}
+ (HttpRequest *)httpRequestWithOtpAuthenticationAndMethod:(NSString *)method
                                               andLocation:(NSString *)location
                                           andOptionalBody:(NSString *)optionalBody
                                            andLocalNumber:(NSString *)localNumber
                                               andPassword:(NSString *)password
                                                andCounter:(int64_t)counter {
    ows_require(method != nil);
    ows_require(location != nil);
    ows_require(password != nil);

    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    if (optionalBody != nil) {
        headers[@"Content-Length"] = [@(optionalBody.length) stringValue];
    }
    headers[@"Authorization"] = [HttpRequest computeOtpAuthorizationTokenForLocalNumber:localNumber
                                                                        andCounterValue:counter
                                                                            andPassword:password];

    HttpRequest *s   = [HttpRequest new];
    s->_method       = method;
    s->_location     = location;
    s->_optionalBody = optionalBody;
    s->_headers      = headers;
    return s;
}

+ (HttpRequest *)httpRequestFromData:(NSData *)data {
    ows_require(data != nil);
    NSUInteger requestSize;
    HttpRequestOrResponse *http = [HttpRequestOrResponse tryExtractFromPartialData:data usedLengthOut:&requestSize];
    checkOperation(http.isRequest && requestSize == data.length);
    return [http request];
}

+ (NSString *)computeOtpAuthorizationTokenForLocalNumber:(PhoneNumber *)localNumber
                                         andCounterValue:(int64_t)counterValue
                                             andPassword:(NSString *)password {
    ows_require(localNumber != nil);
    ows_require(password != nil);

    NSString *rawToken =
        [NSString stringWithFormat:@"%@:%@:%lld",
                                   localNumber,
                                   [CryptoTools computeOtpWithPassword:password andCounter:counterValue],
                                   counterValue];
    return [@"OTP " stringByAppendingString:rawToken.encodedAsUtf8.encodedAsBase64];
}
+ (NSString *)computeBasicAuthorizationTokenForLocalNumber:(NSString *)localNumber andPassword:(NSString *)password {
    NSString *rawToken = [NSString stringWithFormat:@"%@:%@", localNumber, password];
    return [@"Basic " stringByAppendingString:rawToken.encodedAsUtf8.encodedAsBase64];
}

- (NSString *)toHttp {
    NSMutableArray *r = [NSMutableArray array];

    [r addObject:self.method];
    [r addObject:@" "];
    [r addObject:self.location];
    [r addObject:@" HTTP/1.0\r\n"];

    for (NSString *key in self.headers) {
        [r addObject:key];
        [r addObject:@": "];
        [r addObject:(self.headers)[key]];
        [r addObject:@"\r\n"];
    }

    [r addObject:@"\r\n"];
    if (self.optionalBody != nil)
        [r addObject:self.optionalBody];

    return [r componentsJoinedByString:@""];
}
- (NSData *)serialize {
    return self.toHttp.encodedAsUtf8;
}
- (bool)isEqualToHttpRequest:(HttpRequest *)other {
    return [self.toHttp isEqualToString:other.toHttp] && [self.method isEqualToString:other.method] &&
           [self.location isEqualToString:other.location] &&
           (self.optionalBody == other.optionalBody || [self.optionalBody isEqualToString:[other optionalBody]]) &&
           [self.headers isEqualToDictionary:other.headers];
}

- (NSString *)description {
    return
        [NSString stringWithFormat:@"%@ %@%@",
                                   self.method,
                                   self.location,
                                   self.optionalBody == nil ? @"" : self.optionalBody.length == 0 ? @" [empty body]"
                                                                                                   : @" [...body...]"];
}


@end
