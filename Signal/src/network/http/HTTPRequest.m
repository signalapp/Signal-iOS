#import "HTTPRequest.h"
#import "Util.h"
#import "CryptoTools.h"
#import "Constraints.h"
#import "HTTPRequestOrResponse.h"

@interface HTTPRequest ()

@property (strong, nonatomic, readwrite) NSString*     method;
@property (strong, nonatomic, readwrite) NSString*     location;
@property (strong, nonatomic, readwrite) NSString*     optionalBody;
@property (strong, nonatomic, readwrite) NSDictionary* headers;

@end

@implementation HTTPRequest

- (instancetype)initWithMethod:(NSString*)method
                   andLocation:(NSString*)location
                    andHeaders:(NSDictionary*)headers
               andOptionalBody:(NSString*)optionalBody {
    if (self = [super init]) {
        require(method != nil);
        require(location != nil);
        require(headers != nil);
        require((optionalBody == nil) == (headers[@"Content-Length"] == nil));
        require(optionalBody == nil || [[@(optionalBody.length) description] isEqualToString:headers[@"Content-Length"]]);
        
        self.method = method;
        self.location = location;
        self.optionalBody = optionalBody;
        self.headers = headers;
    }
    
    return self;
}

- (instancetype)initUnauthenticatedWithMethod:(NSString*)method
                                  andLocation:(NSString*)location
                              andOptionalBody:(NSString*)optionalBody {
    require(method != nil);
    require(location != nil);
    
    NSMutableDictionary* headers = [[NSMutableDictionary alloc] init];
    if (optionalBody != nil) {
        headers[@"Content-Length"] = [@(optionalBody.length) stringValue];
    }

    return [self initWithMethod:method
                    andLocation:location
                     andHeaders:headers
                andOptionalBody:optionalBody];
}

- (instancetype)initWithBasicAuthenticationAndMethod:(NSString*)method
                                         andLocation:(NSString*)location
                                     andOptionalBody:(NSString*)optionalBody
                                      andLocalNumber:(PhoneNumber*)localNumber
                                         andPassword:(NSString*)password {
    require(method != nil);
    require(location != nil);
    require(password != nil);
    require(localNumber != nil);
    
    NSMutableDictionary* headers = [[NSMutableDictionary alloc] init];
    if (optionalBody != nil) {
        headers[@"Content-Length"] = [@(optionalBody.length) stringValue];
    }
    headers[@"Authorization"] = [HTTPRequest computeBasicAuthorizationTokenForLocalNumber:localNumber
                                                                              andPassword:password];
    
    return [self initWithMethod:method
                    andLocation:location
                     andHeaders:headers
                andOptionalBody:optionalBody];
}

- (instancetype)initWithOTPAuthenticationAndMethod:(NSString*)method
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
        headers[@"Content-Length"] = [@(optionalBody.length) stringValue];
    }
    headers[@"Authorization"] = [HTTPRequest computeOTPAuthorizationTokenForLocalNumber:localNumber
                                                                        andCounterValue:counter
                                                                            andPassword:password];
    
    return [self initWithMethod:method
                    andLocation:location
                     andHeaders:headers
                andOptionalBody:optionalBody];
}

- (instancetype)initFromData:(NSData*)data {
    require(data != nil);
    NSUInteger requestSize;
    HTTPRequestOrResponse* http = [HTTPRequestOrResponse tryExtractFromPartialData:data usedLengthOut:&requestSize];
    checkOperation(http.isRequest && requestSize == data.length);
    return [http request];
}

+ (NSString*)computeOTPAuthorizationTokenForLocalNumber:(PhoneNumber*)localNumber
                                        andCounterValue:(int64_t)counterValue
                                            andPassword:(NSString*)password {
    require(localNumber != nil);
    require(password != nil);
    
    NSString* rawToken = [NSString stringWithFormat:@"%@:%@:%lld",
                          localNumber.toE164,
                          [CryptoTools computeOTPWithPassword:password andCounter:counterValue],
                          counterValue];
    return [@"OTP " stringByAppendingString:rawToken.encodedAsUtf8.encodedAsBase64];
}

+ (NSString*)computeBasicAuthorizationTokenForLocalNumber:(PhoneNumber*)localNumber andPassword:(NSString*)password {
    NSString* rawToken = [NSString stringWithFormat:@"%@:%@",
                          localNumber.toE164,
                          password];
    return [@"Basic " stringByAppendingString:rawToken.encodedAsUtf8.encodedAsBase64];
}

- (NSString*)toHTTP {
    NSMutableArray* r = [[NSMutableArray alloc] init];
    
    [r addObject:self.method];
    [r addObject:@" "];
    [r addObject:self.location];
    [r addObject:@" HTTP/1.0\r\n"];
    
    for (NSString* key in self.headers) {
        [r addObject:key];
        [r addObject:@": "];
        [r addObject:(self.headers)[key]];
        [r addObject:@"\r\n"];
    }
    
    [r addObject:@"\r\n"];
    if (self.optionalBody != nil) [r addObject:self.optionalBody];
    
    return [r componentsJoinedByString:@""];
}

- (NSData*)serialize {
    return self.toHTTP.encodedAsUtf8;
}

- (bool)isEqualToHTTPRequest:(HTTPRequest*)other {
    return [self.toHTTP isEqualToString:other.toHTTP]
    && [self.method isEqualToString:other.method]
    && [self.location isEqualToString:other.location]
    && (self.optionalBody == other.optionalBody || [self.optionalBody isEqualToString:[other optionalBody]])
    && [self.headers isEqualToDictionary:other.headers];
}

- (NSString*)description {
    return [NSString stringWithFormat:@"%@ %@%@",
            self.method,
            self.location,
            self.optionalBody == nil ? @""
                                     : self.optionalBody.length == 0 ? @" [empty body]"
                                     : @" [...body...]"];
}


@end
