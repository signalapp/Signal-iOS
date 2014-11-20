#import "InteractiveLabel.h"

@interface InteractiveLabel ()

@property (nonatomic, copy) void (^pasteBlock) (id sender);
@property (nonatomic, copy) void (^copyBlock)  (id sender);

@end

@implementation InteractiveLabel

#pragma mark Menu Setup

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    
    if (self) {
        [self setupGestureRecognizer];
    }
    
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [self setupGestureRecognizer];
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (void)setupGestureRecognizer {
    UILongPressGestureRecognizer *recognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                             action:@selector(didRegisterLongPress:)];
    [self addGestureRecognizer:recognizer];
}


- (void)didRegisterLongPress:(UILongPressGestureRecognizer*)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        [self becomeFirstResponder];
        [[UIMenuController sharedMenuController] setTargetRect:self.frame inView:self.superview];
        [[UIMenuController sharedMenuController] setMenuVisible:YES animated:YES];

    }
}

//todo: set custom dispaly logic via block for runtime decision
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(paste:)) return nil != self.pasteBlock;
    if (action == @selector(copy:)) return nil != self.copyBlock;
    
    return NO;
}

#pragma mark Block Handling

- (void)onPaste:(void (^)(id sender))pasteAction {
    self.pasteBlock = pasteAction;
}

- (void)onCopy:(void (^)(id sender))copyAction {
    self.copyBlock = copyAction;
}

- (void)paste:(id)sender {
    if (self.pasteBlock) {
        self.pasteBlock(sender);
    }
}

@end
