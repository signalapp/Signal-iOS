#import <Foundation/Foundation.h>
#import "CallTermination.h"
#import "CallProgress.h"

#define TXT_IN_CALL_CONNECTING  NSLocalizedString(@"IN_CALL_CONNECTING", @"")
#define TXT_IN_CALL_RINGING     NSLocalizedString(@"IN_CALL_RINGING", @"")
#define TXT_IN_CALL_SECURING    NSLocalizedString(@"IN_CALL_SECURING", @"")
#define TXT_IN_CALL_TALKING     NSLocalizedString(@"IN_CALL_TALKING", @"")
#define TXT_IN_CALL_TERMINATED  NSLocalizedString(@"IN_CALL_TERMINATED", @"")

#define TXT_END_CALL_LOGIN_FAILED                   NSLocalizedString(@"END_CALL_LOGIN_FAILED", @"")
#define TXT_END_CALL_STALE_SESSION                  NSLocalizedString(@"END_CALL_STALE_SESSION", @"")
#define TXT_END_CALL_NO_SUCH_USER                   NSLocalizedString(@"END_CALL_NO_SUCH_USER", @"")
#define TXT_END_CALL_RESPONDER_IS_BUSY              NSLocalizedString(@"END_CALL_RESPONDER_IS_BUSY", @"")
#define TXT_END_CALL_REJECTED_LOCAL                 NSLocalizedString(@"END_CALL_REJECTED_LOCAL", @"")
#define TXT_END_CALL_REJECTED_REMOTE                NSLocalizedString(@"END_CALL_REJECTED_REMOTE", @"")
#define TXT_END_CALL_RECIPIENT_UNAVAILABLE          NSLocalizedString(@"END_CALL_RECIPIENT_UNAVAILABLE", @"")
#define TXT_END_CALL_UNCATEGORIZED_FAILURE          NSLocalizedString(@"END_CALL_UNCATEGORIZED_FAILURE", @"")
#define TXT_END_CALL_BAD_INTERACTION_WITH_SERVER    NSLocalizedString(@"END_CALL_BAD_INTERACTION_WITH_SERVER", @"")
#define TXT_END_CALL_HANDSHAKE_FAILED               NSLocalizedString(@"END_CALL_HANDSHAKE_FAILED", @"")
#define TXT_END_CALL_HANGUP_REMOTE                  NSLocalizedString(@"END_CALL_HANGUP_REMOTE", @"")
#define TXT_END_CALL_HANGUP_LOCAL                   NSLocalizedString(@"END_CALL_HANGUP_LOCAL", @"")
#define TXT_END_CALL_REPLACED_BY_NEXT               NSLocalizedString(@"END_CALL_REPLACED_BY_NEXT", @"")
// @todo: some languages probably don't prefix this sort of thing
#define TXT_END_CALL_MESSAGE_FROM_SERVER_PREFIX     NSLocalizedString(@"END_CALL_MESSAGE_FROM_SERVER_PREFIX", @"")

#pragma mark - Menu Table Cell Titles

#define MAIN_MENU_OPTION_RECENT_CALLS	NSLocalizedString(@"MAIN_MENU_OPTION_RECENT_CALLS",@"")
#define MAIN_MENU_OPTION_FAVOURITES		NSLocalizedString(@"MAIN_MENU_OPTION_FAVOURITES",@"")
#define MAIN_MENU_OPTION_CONTACTS		NSLocalizedString(@"MAIN_MENU_OPTION_CONTACTS",@"")
#define MAIN_MENU_OPTION_DIALER			NSLocalizedString(@"MAIN_MENU_OPTION_DIALER",@"")
#define MAIN_MENU_INVITE_CONTACTS		NSLocalizedString(@"MAIN_MENU_INVITE_CONTACTS",@"")

#define MAIN_MENU_OPTION_SETTINGS		NSLocalizedString(@"MAIN_MENU_OPTION_SETTINGS",@"")
#define MAIN_MENU_OPTION_ABOUT			NSLocalizedString(@"MAIN_MENU_OPTION_ABOUT",@"")
#define MAIN_MENU_OPTION_REPORT_BUG		NSLocalizedString(@"MAIN_MENU_OPTION_REPORT_BUG",@"")
#define MAIN_MENU_OPTION_BLOG			NSLocalizedString(@"MAIN_MENU_OPTION_BLOG",@"")

#pragma mark - View Controller Titles

#define WHISPER_NAV_BAR_TITLE			NSLocalizedString(@"WHISPER_NAV_BAR_TITLE", @"Title for home feed view controller")
#define CONTACT_BROWSE_NAV_BAR_TITLE	NSLocalizedString(@"CONTACT_BROWSE_NAV_BAR_TITLE", @"Title for contact browse view controller")
#define KEYPAD_NAV_BAR_TITLE			NSLocalizedString(@"KEYPAD_NAV_BAR_TITLE", @"Title for keypad view controller")
#define RECENT_NAV_BAR_TITLE			NSLocalizedString(@"RECENT_NAV_BAR_TITLE", @"Title for recent calls view controller")
#define SETTINGS_NAV_BAR_TITLE			NSLocalizedString(@"SETTINGS_NAV_BAR_TITLE", @"Title for recent calls view controller")
#define FAVOURITES_NAV_BAR_TITLE		NSLocalizedString(@"FAVOURITES_NAV_BAR_TITLE", @"Title for favourites view controller")

#pragma mark - Contact Detail Communication Types

#define CONTACT_DETAIL_COMM_TYPE_EMAIL	NSLocalizedString(@"CONTACT_DETAIL_COMM_TYPE_EMAIL", @"")
#define CONTACT_DETAIL_COMM_TYPE_SECURE NSLocalizedString(@"CONTACT_DETAIL_COMM_TYPE_SECURE", @"")
#define CONTACT_DETAIL_COMM_TYPE_INSECURE NSLocalizedString(@"CONTACT_DETAIL_COMM_TYPE_INSECURE", @"")
#define CONTACT_DETAIL_COMM_TYPE_NOTES  NSLocalizedString(@"CONTACT_DETAIL_COMM_TYPE_NOTES", @"")

#pragma mark - Dialer

#define DIALER_NUMBER_1 NSLocalizedString(@"DIALER_NUMBER_1", @"")
#define DIALER_NUMBER_2 NSLocalizedString(@"DIALER_NUMBER_2", @"")
#define DIALER_NUMBER_3 NSLocalizedString(@"DIALER_NUMBER_3", @"")
#define DIALER_NUMBER_4 NSLocalizedString(@"DIALER_NUMBER_4", @"")
#define DIALER_NUMBER_5 NSLocalizedString(@"DIALER_NUMBER_5", @"")
#define DIALER_NUMBER_6 NSLocalizedString(@"DIALER_NUMBER_6", @"")
#define DIALER_NUMBER_7 NSLocalizedString(@"DIALER_NUMBER_7", @"")
#define DIALER_NUMBER_8 NSLocalizedString(@"DIALER_NUMBER_8", @"")
#define DIALER_NUMBER_9 NSLocalizedString(@"DIALER_NUMBER_9", @"")
#define DIALER_NUMBER_0 NSLocalizedString(@"DIALER_NUMBER_0", @"")
#define DIALER_NUMBER_PLUS NSLocalizedString(@"DIALER_NUMBER_PLUS", @"")
#define DIALER_NUMBER_POUND NSLocalizedString(@"DIALER_NUMBER_POUND", @"")
#define TXT_ADD_CONTACT NSLocalizedString(@"TXT_ADD_CONTACT", @"")
#define CALL_BUTTON_TITLE NSLocalizedString(@"CALL_BUTTON_TITLE", @"")

#define DIALER_CALL_BUTTON_TITLE NSLocalizedString(@"DIALER_CALL_BUTTON_TITLE", @"")

#pragma mark - General Purpose

#define TXT_CANCEL_TITLE NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
#define TXT_SEARCH_PLACEHOLDER_TEXT NSLocalizedString(@"TXT_SEARCH_PLACEHOLDER_TEXT", @"")
#define UNKNOWN_CONTACT_NAME NSLocalizedString(@"UNKNOWN_CONTACT_NAME", @"")
#define TXT_DATESTRING_TODAY NSLocalizedString(@"DATESTRING_TODAY", @"")

#pragma mark - Inbox View

#define INBOX_VIEW_TUTORIAL_LABEL_TOP NSLocalizedString(@"INBOX_VIEW_TUTORIAL_LABEL_TOP", @"")
#define INBOX_VIEW_TUTORIAL_LABEL_MIDDLE NSLocalizedString(@"INBOX_VIEW_TUTORIAL_LABEL_MIDDLE", @"")

#define TABLE_SECTION_TITLE_REGISTERED NSLocalizedString(@"TABLE_SECTION_TITLE_REGISTERED", @"")
#define TABLE_SECTION_TITLE_UNREGISTERED NSLocalizedString(@"TABLE_SECTION_TITLE_UNREGISTERED", @"")

#pragma mark - Home View footer cell

#define HOME_FOOTER_FIRST_MESSAGE_CALLS_UNSORTED NSLocalizedString(@"HOME_FOOTER_FIRST_MESSAGE_CALLS_UNSORTED", @"")
#define HOME_FOOTER_SECOND_MESSAGE_CALLS_UNSORTED NSLocalizedString(@"HOME_FOOTER_SECOND_MESSAGE_CALLS_UNSORTED", @"")
#define HOME_FOOTER_SECOND_MESSAGE_CALL_UNSORTED NSLocalizedString(@"HOME_FOOTER_SECOND_MESSAGE_CALL_UNSORTED", @"")
#define HOME_FOOTER_FIRST_MESSAGE_CALLS_NIL NSLocalizedString(@"HOME_FOOTER_FIRST_MESSAGE_CALLS_NIL", @"")
#define HOME_FOOTER_SECOND_MESSAGE_CALLS_NIL NSLocalizedString(@"HOME_FOOTER_SECOND_MESSAGE_CALLS_NIL", @"")

#pragma mark - Settings View

#define SETTINGS_NUMBER_PREFIX NSLocalizedString(@"SETTINGS_NUMBER_PREFIX", @"")
#define SETTINGS_LOG_CLEAR_TITLE NSLocalizedString(@"SETTINGS_LOG_CLEAR_TITLE", @"")
#define SETTINGS_LOG_CLEAR_MESSAGE NSLocalizedString(@"SETTINGS_LOG_CLEAR_MESSAGE", @"")
#define SETTINGS_LOG_CLEAR_CONFIRM NSLocalizedString(@"OK", @"")

#define SETTINGS_SENDLOG NSLocalizedString(@"SETTINGS_SENDLOG", @"")

#define SETTINGS_SENDLOG_WAITING NSLocalizedString(@"SETTINGS_SENDLOGS_WAITING", @"")
#define SETTINGS_SENDLOG_ALERT_TITLE NSLocalizedString(@"SETTINGS_SENDLOG", @"")
#define SETTINGS_SENDLOG_ALERT_BODY NSLocalizedString(@"SETTINGS_SENDLOG_ALERT_BODY",@"")
#define SETTINGS_SENDLOG_ALERT_PASTE NSLocalizedString(@"SETTINGS_SENDLOG_ALERT_PASTE", @"")
#define SETTINGS_SENDLOG_ALERT_EMAIL NSLocalizedString(@"SETTINGS_SENDLOG_ALERT_EMAIL", @"")
#define SETTINGS_SENDLOG_FAILED_TITLE NSLocalizedString(@"SETTINGS_SENDLOG_FAILED_TITLE", @"")
#define SETTINGS_SENDLOG_FAILED_BODY NSLocalizedString(@"SETTINGS_SENDLOG_FAILED_BODY", @"")
#define SETTINGS_SENDLOG_FAILED_DISMISS NSLocalizedString(@"OK", @"")


#pragma mark - Registration

#define REGISTER_CC_ERR_ALERT_VIEW_TITLE NSLocalizedString(@"REGISTER_CC_ERR_ALERT_VIEW_TITLE", @"")
#define REGISTER_CC_ERR_ALERT_VIEW_MESSAGE NSLocalizedString(@"REGISTER_CC_ERR_ALERT_VIEW_MESSAGE", @"")
#define REGISTER_CC_ERR_ALERT_VIEW_DISMISS NSLocalizedString(@"OK", @"")
#define CONTINUE_TO_WHISPER_TITLE NSLocalizedString(@"CONTINUE_TO_WHISPER_TITLE", @"")

#define REGISTER_BUTTON_TITLE NSLocalizedString(@"REGISTER_BUTTON_TITLE", @"")
#define CHALLENGE_CODE_BUTTON_TITLE NSLocalizedString(@"CHALLENGE_CODE_BUTTON_TITLE", @"")

#define END_CALL_BUTTON_TITLE NSLocalizedString(@"END_CALL_BUTTON_TITLE", @"")
#define ANSWER_CALL_BUTTON_TITLE NSLocalizedString(@"ANSWER_CALL_BUTTON_TITLE", @"")
#define REJECT_CALL_BUTTON_TITLE NSLocalizedString(@"REJECT_CALL_BUTTON_TITLE", @"")

#define REGISTER_ERROR_ALERT_VIEW_TITLE NSLocalizedString(@"REGISTRATION_ERROR", @"")
#define REGISTER_ERROR_ALERT_VIEW_BODY  NSLocalizedString(@"REGISTRATION_BODY", @"")
#define REGISTER_ERROR_ALERT_VIEW_DISMISS NSLocalizedString(@"OK", @"")

#define REGISTER_CHALLENGE_ALERT_VIEW_TITLE NSLocalizedString(@"REGISTER_CHALLENGE_ALERT_VIEW_TITLE", @"")
#define REGISTER_CHALLENGE_ALERT_VIEW_BODY NSLocalizedString(@"REGISTER_CHALLENGE_ALERT_VIEW_BODY", @"")

#define REGISTER_CHALLENGE_ALERT_DISMISS NSLocalizedString(@"OK", @"")

#pragma mark - Invite Users

#define INVITE_USERS_ACTION_SHEET_TITLE NSLocalizedString(@"INVITE_USERS_ACTION_SHEET_TITLE", @"");
#define INVITE_USERS_MESSAGE NSLocalizedString(@"INVITE_USERS_MESSAGE", @"");

#pragma mark - Invite User Modal

#define INVITE_USER_MODAL_TITLE         NSLocalizedString(@"INVITE_USER_MODAL_TITLE",@"")
#define INVITE_USER_MODAL_BUTTON_CANCEL NSLocalizedString(@"INVITE_USER_MODAL_BUTTON_CANCEL",@"")
#define INVITE_USER_MODAL_BUTTON_INVITE NSLocalizedString(@"INVITE_USER_MODAL_BUTTON_INVITE",@"")
#define INVITE_USER_MODAL_TEXT          NSLocalizedString(@"INVITE_USER_MODAL_TEXT",@"")

#pragma mark - Contact Intersection

#define TIMEOUT                         NSLocalizedString(@"TIMEOUT",@"")
#define TIMEOUT_CONTACTS_DETAIL         NSLocalizedString(@"TIMEOUT_CONTACTS_DETAIL", @"")

NSDictionary* makeCallProgressLocalizedTextDictionary(void);
NSDictionary* makeCallTerminationLocalizedTextDictionary(void);

