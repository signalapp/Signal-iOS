#import <Foundation/Foundation.h>

@interface HTTPResponse : NSObject

@property (nonatomic, readonly, getter=getStatusCode)               NSUInteger    statusCode;
@property (strong, nonatomic, readonly, getter=getStatusText)       NSString*     statusText;
@property (strong, nonatomic, readonly, getter=getHeaders)          NSDictionary* headers;
@property (strong, nonatomic, readonly, getter=getOptionalBodyText) NSString*     optionalBodyText;
@property (strong, nonatomic, readonly, getter=getOptionalBodyData) NSData*       optionalBodyData;

- (instancetype)initFromStatusCode:(NSUInteger)statusCode
                     andStatusText:(NSString*)statusText
                        andHeaders:(NSDictionary*)headers
               andOptionalBodyText:(NSString*)optionalBody;
- (instancetype)initFromStatusCode:(NSUInteger)statusCode
                     andStatusText:(NSString*)statusText
                        andHeaders:(NSDictionary*)headers
               andOptionalBodyData:(NSData*)optionalBody;

+ (HTTPResponse*)httpResponseFromData:(NSData*)data;
+ (HTTPResponse*)httpResponse200Ok;
+ (HTTPResponse*)httpResponse200OkWithOptionalBody:(NSString*)optionalBody;
+ (HTTPResponse*)httpResponse501NotImplemented;
+ (HTTPResponse*)httpResponse500InternalServerError;

- (NSData*)serialize;
- (bool)isOkResponse;
- (bool)hasBody;

@end
