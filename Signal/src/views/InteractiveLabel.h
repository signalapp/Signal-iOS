#import <Foundation/Foundation.h>

@interface InteractiveLabel : UILabel

-(void) onPaste:(void(^)(id sender)) pasteBlock;
-(void) onCopy:(void(^)(id sender))  copyBlock;

@end
