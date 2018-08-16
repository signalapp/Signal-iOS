//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSContactShareButtonsView.h"
#import "Signal-Swift.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIColor+OWS.h>
#import <SignalServiceKit/OWSContact.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactShareButtonsView ()

@property (nonatomic, readonly) ContactShareViewModel *contactShare;
@property (nonatomic, weak) id<OWSContactShareButtonsViewDelegate> delegate;

@property (nonatomic, readonly) OWSContactsManager *contactsManager;

@property (nonatomic, nullable) UIView *buttonView;

@end

#pragma mark -

@implementation OWSContactShareButtonsView

- (instancetype)initWithContactShare:(ContactShareViewModel *)contactShare
                            delegate:(id<OWSContactShareButtonsViewDelegate>)delegate
{
    self = [super init];

    if (self) {
        _delegate = delegate;
        _contactShare = contactShare;
        _contactsManager = [Environment current].contactsManager;

        [self createContents];
    }

    return self;
}

#pragma mark -

+ (BOOL)hasSendTextButton:(ContactShareViewModel *)contactShare contactsManager:(OWSContactsManager *)contactsManager
{
    OWSAssert(contactShare);
    OWSAssert(contactsManager);

    return [contactShare systemContactsWithSignalAccountPhoneNumbers:contactsManager].count > 0;
}

+ (BOOL)hasInviteButton:(ContactShareViewModel *)contactShare contactsManager:(OWSContactsManager *)contactsManager
{
    OWSAssert(contactShare);
    OWSAssert(contactsManager);

    return [contactShare systemContactPhoneNumbers:contactsManager].count > 0;
}

+ (BOOL)hasAddToContactsButton:(ContactShareViewModel *)contactShare
{
    OWSAssert(contactShare);

    return [contactShare e164PhoneNumbers].count > 0;
}

+ (BOOL)hasAnyButton:(ContactShareViewModel *)contactShare
{
    OWSAssert(contactShare);

    OWSContactsManager *contactsManager = [Environment current].contactsManager;

    return [self hasAnyButton:contactShare contactsManager:contactsManager];
}

+ (BOOL)hasAnyButton:(ContactShareViewModel *)contactShare contactsManager:(OWSContactsManager *)contactsManager
{
    OWSAssert(contactShare);

    return ([self hasSendTextButton:contactShare contactsManager:contactsManager] ||
        [self hasInviteButton:contactShare contactsManager:contactsManager] ||
        [self hasAddToContactsButton:contactShare]);
}

+ (CGFloat)bubbleHeight
{
    return self.buttonHeight;
}

+ (CGFloat)buttonHeight
{
    return MAX(44.f, self.buttonFont.lineHeight + self.buttonVMargin * 2);
}

+ (UIFont *)buttonFont
{
    return [UIFont ows_dynamicTypeBodyFont].ows_mediumWeight;
}

+ (CGFloat)buttonVMargin
{
    return 5;
}

- (void)createContents
{
    OWSAssert([OWSContactShareButtonsView hasAnyButton:self.contactShare contactsManager:self.contactsManager]);

    self.layoutMargins = UIEdgeInsetsZero;
    self.backgroundColor = Theme.conversationButtonBackgroundColor;

    UILabel *label = [UILabel new];
    self.buttonView = label;
    if ([OWSContactShareButtonsView hasSendTextButton:self.contactShare contactsManager:self.contactsManager]) {
        label.text
            = NSLocalizedString(@"ACTION_SEND_MESSAGE", @"Label for button that lets you send a message to a contact.");
    } else if ([OWSContactShareButtonsView hasInviteButton:self.contactShare contactsManager:self.contactsManager]) {
        label.text = NSLocalizedString(@"ACTION_INVITE", @"Label for 'invite' button in contact view.");
    } else if ([OWSContactShareButtonsView hasAddToContactsButton:self.contactShare]) {
        label.text = NSLocalizedString(@"CONVERSATION_VIEW_ADD_TO_CONTACTS_OFFER",
            @"Message shown in conversation view that offers to add an unknown user to your phone's contacts.");
    } else {
        OWSFail(@"%@ unexpected button state.", self.logTag);
    }
    label.font = OWSContactShareButtonsView.buttonFont;
    label.textColor = (Theme.isDarkThemeEnabled ? UIColor.ows_whiteColor : UIColor.ows_materialBlueColor);
    label.textAlignment = NSTextAlignmentCenter;
    [self addSubview:label];
    [label ows_autoPinToSuperviewEdges];
    [label autoSetDimension:ALDimensionHeight toSize:OWSContactShareButtonsView.buttonHeight];

    self.userInteractionEnabled = YES;
    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
    [self addGestureRecognizer:tap];
}

- (BOOL)handleTapGesture:(UITapGestureRecognizer *)sender
{
    if (!self.buttonView) {
        return NO;
    }
    CGPoint location = [sender locationInView:self.buttonView];
    if (!CGRectContainsPoint(self.buttonView.bounds, location)) {
        return NO;
    }

    if ([OWSContactShareButtonsView hasSendTextButton:self.contactShare contactsManager:self.contactsManager]) {
        [self.delegate didTapSendMessageToContactShare:self.contactShare];
    } else if ([OWSContactShareButtonsView hasInviteButton:self.contactShare contactsManager:self.contactsManager]) {
        [self.delegate didTapSendInviteToContactShare:self.contactShare];
    } else if ([OWSContactShareButtonsView hasAddToContactsButton:self.contactShare]) {
        [self.delegate didTapShowAddToContactUIForContactShare:self.contactShare];
    } else {
        OWSFail(@"%@ unexpected button tap.", self.logTag);
    }

    return YES;
}

@end

NS_ASSUME_NONNULL_END
