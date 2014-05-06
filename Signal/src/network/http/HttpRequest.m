#import "HttpRequest.h"
#import "Util.h"
#import "CryptoTools.h"
#import "Constraints.h"
#import "HttpRequestOrResponse.h"

@interface HttpRequest ()
@property NSString*     method;
@property NSString*     location;
@property NSString*     optionalBody;
@property NSDictionary* headers;

@end

@implementation HttpRequest

+(HttpRequest*)httpRequestWithMethod:(NSString*)method andLocation:(NSString*)location andHeaders:(NSDictionary*)headers andOptionalBody:(NSString*)optionalBody {
    require(method != nil);
    require(location != nil);
    require(headers != nil);
    require((optionalBody == nil) == ([headers objectForKey:@"Content-Length"] == nil));
    require(optionalBody == nil || [[[NSNumber numberWithUnsignedInteger:[optionalBody length]] description] isEqualToString:[headers objectForKey:@"Content-Length"]]);
    
    HttpRequest* s = [HttpRequest new];
    s->_method = method;
    s->_location = location;
    s->_optionalBody = optionalBody;
    s->_headers = headers;
    return s;
}
+(HttpRequest*)httpRequestUnauthenticatedWithMethod:(NSString*)method
                                        andLocation:(NSString*)location
                                    andOptionalBody:(NSString*)optionalBody {
    require(method != nil);
    require(location != nil);
    
    NSMutableDictionary* headers = [NSMutableDictionary dictionary];
    if (optionalBody != nil) {
        [headers setObject:[[NSNumber numberWithLongLong:[optionalBody length]] stringValue] forKey:@"Content-Length"];
    }

    HttpRequest* s = [HttpRequest new];
    s->_method = method;
    s->_location = location;
    s->_optionalBody = optionalBody;
    s->_headers = headers;
    return s;
}
+(HttpRequest*)httpRequestWithBasicAuthenticationAndMethod:(NSString*)method
                                               andLocation:(NSString*)location
                                           andOptionalBody:(NSString*)optionalBody
                                            andLocalNumber:(PhoneNumber*)localNumber
                                               andPassword:(NSString*)password {
    require(method != nil);
    require(location != nil);
    require(password != nil);
    require(localNumber != nil);
    
    NSMutableDictionary* headers = [NSMutableDictionary dictionary];
    if (optionalBody != nil) {
        [headers setObject:[[NSNumber numberWithLongLong:[optionalBody length]] stringValue] forKey:@"Content-Length"];
    }
    [headers setObject:[HttpRequest computeBasicAuthorizationTokenForLocalNumber:localNumber andPassword:password] forKey:@"Authorization"];
    
    HttpRequest* s = [HttpRequest new];
    s->_method = method;
    s->_location = location;
    s->_optionalBody = optionalBody;
    s->_headers = headers;
    return s;
}
+(HttpRequest*)httpRequestWithOtpAuthenticationAndMethod:(NSString*)method
                                             andLocation:(NSString*)location
                                         andOptionalBody:(NSString*)optionalBody
                                          andLocalNumber:(PhoneNumber*)localNumber
                                             andPassword:(NSString*)password
                                              andCounter:(int64_t)counter {
    require(method != nil);
    require(location != nil);
    require(password != nil);
    
    NSMutableDictionary* headers = [NSMutableDictionary dictionary];
    if (optionalBody != nil) {
        [headers setObject:[[NSNumber numberWithLongLong:[optionalBody length]] stringValue] forKey:@"Content-Length"];
    }
    [headers setObject:[HttpRequest computeOtpAuthorizationTokenForLocalNumber:localNumber andCounterValue:counter andPassword:password] forKey:@"Authorization"];
    
    HttpRequest* s = [HttpRequest new];
    s->_method = method;
    s->_location = location;
    s->_optionalBody = optionalBody;
    s->_headers = headers;
    return s;
}

+(HttpRequest*) httpRequestFromData:(NSData*)data {
    require(data != nil);
    NSUInteger requestSize;
    HttpRequestOrResponse* http = [HttpRequestOrResponse tryExtractFromPartialData:data usedLengthOut:&requestSize];
    checkOperation([http isRequest] && requestSize == [data length]);
    return [http request];
}

+(NSString*) computeOtpAuthorizationTokenForLocalNumber:(PhoneNumber*)localNumber
                                        andCounterValue:(int64_t)counterValue
                                            andPassword:(NSString*)password {
    require(localNumber != nil);
    require(password != nil);
    
    NSString* rawToken = [NSString stringWithFormat:@"%@:%@:%lld",
                          [localNumber toE164],
                          [CryptoTools computeOtpWithPassword:password andCounter:counterValue],
                          counterValue];
    return [@"OTP " stringByAppendingString:[[rawToken encodedAsUtf8] encodedAsBase64]];
}
+(NSString*) computeBasicAuthorizationTokenForLocalNumber:(PhoneNumber*)localNumber andPassword:(NSString*)password {
    NSString* rawToken = [NSString stringWithFormat:@"%@:%@",
                          [localNumber toE164],
                          password];
    return [@"Basic " stringByAppendingString:[[rawToken encodedAsUtf8] encodedAsBase64]];
}

-(NSString*) toHttp {
    NSMutableArray* r = [NSMutableArray array];
    
    [r addObject:self.method];
    [r addObject:@" "];
    [r addObject:self.location];
    [r addObject:@" HTTP/1.0\r\n"];
    
    for (NSString* key in self.headers) {
        [r addObject:key];
        [r addObject:@": "];
        [r addObject:[self.headers objectForKey:key]];
        [r addObject:@"\r\n"];
    }
    
    [r addObject:@"\r\n"];
    if (self.optionalBody != nil) [r addObject:self.optionalBody];
    
    return [r componentsJoinedByString:@""];
}
-(NSData*) serialize {
    return [[self toHttp] encodedAsUtf8];
}
-(bool) isEqualToHttpRequest:(HttpRequest *)other {
    return [[self toHttp] isEqualToString:[other toHttp]]
        && [self.method isEqualToString:other.method]
        && [self.location isEqualToString:other.location]
        && (self.optionalBody == other.optionalBody || [self.optionalBody isEqualToString:[other optionalBody]])
        && [self.headers isEqualToDictionary:other.headers];
}

-(NSString*) description {
    return [NSString stringWithFormat:@"%@ %@%@",
            self.method,
            self.location,
            self.optionalBody == nil ? @""
                : [self.optionalBody length] == 0 ? @" [empty body]"
                : @" [...body...]"];
}

@end
