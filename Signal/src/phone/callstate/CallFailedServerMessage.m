#import "CallFailedServerMessage.h"
#import "Util.h"

@interface CallFailedServerMessage ()

@property (readwrite, nonatomic) NSString* text;

@end

@implementation CallFailedServerMessage

- (instancetype)initWithText:(NSString*)text {
    self = [super init];
	
    if (self) {
        require(text != nil);
        self.text = text;
    }
    
    return self;
}

@end
