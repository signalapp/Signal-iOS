//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ContactShareViewModel;

@protocol OWSContactShareButtonsViewDelegate <NSObject>

- (void)didTapSendMessageToContactShare:(ContactShareViewModel *)contactShare;
- (void)didTapSendInviteToContactShare:(ContactShareViewModel *)contactShare;
- (void)didTapShowAddToContactUIForContactShare:(ContactShareViewModel *)contactShare;

@end

#pragma mark -

@interface OWSContactShareButtonsView : UIView

- (instancetype)initWithContactShare:(ContactShareViewModel *)contactShare
                            delegate:(id<OWSContactShareButtonsViewDelegate>)delegate;

+ (CGFloat)bubbleHeight;

// Returns YES IFF the tap was handled.
- (BOOL)handleTapGesture:(UITapGestureRecognizer *)sender;

+ (BOOL)hasAnyButton:(ContactShareViewModel *)contactShare;

@end

NS_ASSUME_NONNULL_END
