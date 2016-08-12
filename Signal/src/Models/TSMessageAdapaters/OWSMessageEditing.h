//  Copyright © 2016 Open Whisper Systems. All rights reserved.

@protocol OWSMessageEditing <NSObject>

- (BOOL)canPerformEditingAction:(SEL)action;
- (void)performEditingAction:(SEL)action;

@end
