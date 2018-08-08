#import <Foundation/Foundation.h>

@interface HttpResponse : NSObject {
@private NSUInteger statusCode;
@private NSString* statusText;
@private NSDictionary* headers;
@private NSString* optionalBodyText;
@private NSData* optionalBodyData;
}

+(HttpResponse*) httpResponseFromStatusCode:(NSUInteger)statusCode
                              andStatusText:(NSString*)statusText
                                 andHeaders:(NSDictionary*)headers
                        andOptionalBodyText:(NSString*)optionalBody;
+(HttpResponse*) httpResponseFromStatusCode:(NSUInteger)statusCode
                              andStatusText:(NSString*)statusText
                                 andHeaders:(NSDictionary*)headers
                        andOptionalBodyData:(NSData*)optionalBody;
+(HttpResponse*) httpResponseFromData:(NSData*)data;
+(HttpResponse*) httpResponse200Ok;
+(HttpResponse*) httpResponse200OkWithOptionalBody:(NSString*)optionalBody;
+(HttpResponse*) httpResponse501NotImplemented;
+(HttpResponse*) httpResponse500InternalServerError;

-(NSUInteger) getStatusCode;
-(NSDictionary*) getHeaders;
-(NSString*) getOptionalBodyText;
-(NSData*) getOptionalBodyData;
-(NSData*) serialize;
-(NSString*) getStatusText;
-(bool) isOkResponse;
-(bool) hasBody;

@end
