#import "CallFailedServerMessage.h"
#import "Util.h"

@implementation CallFailedServerMessage

@synthesize text;

+(CallFailedServerMessage*) callFailedServerMessageWithText:(NSString*)text {
    require(text != nil);
    
    CallFailedServerMessage* instance = [CallFailedServerMessage new];
    instance->text = text;
    return instance;
}

@end
