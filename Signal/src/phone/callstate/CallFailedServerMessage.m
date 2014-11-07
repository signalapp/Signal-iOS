#import "CallFailedServerMessage.h"
#import "Util.h"

@interface CallFailedServerMessage ()

@property (readwrite, nonatomic) NSString* text;

@end

@implementation CallFailedServerMessage

- (instancetype)initWithText:(NSString*)text {
    if (self = [super init]) {
        require(text != nil);
        self.text = text;
    }
    
    return self;
}

@end
