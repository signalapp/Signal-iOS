#import "ContactDetailViewController.h"
#import "ContactsManager.h"
#import "InCallViewController.h"
#import "UIUtil.h"

#define CONTACT_DETAIL_CELL_HEIGHT 49

static NSString* const DEFAULT_CONTACT_IMAGE = @"DefaultContactImage.png";
static NSString* const DETAIL_TABLE_CELL_IDENTIFIER = @"ContactDetailTableViewCell";
static NSString* const MAIL_URL_PREFIX = @"mailto://";

static NSString* const FAVOURITE_TRUE_ICON_NAME = @"favourite_true_icon";
static NSString* const FAVOURITE_FALSE_ICON_NAME = @"favourite_false_icon";

@interface ContactDetailViewController ()

@property (strong, readwrite, nonatomic) Contact* contact;

@end

@implementation ContactDetailViewController

@synthesize contactImageView = _contactImageView;

- (instancetype)initWithContact:(Contact*)contact {
    self = [super init];
	
    if (self) {
        self.contact = contact;
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.contactInfoTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (void)viewWillAppear:(BOOL)animated {
	
    if (self.contact) {
        self.navigationController.navigationBar.barTintColor = UIUtil.darkBackgroundColor;
        self.navigationController.navigationBar.tintColor = UIColor.whiteColor;
        self.navigationController.navigationBar.translucent = NO;
        self.contactNameLabel.text = self.contact.fullName;
        if (self.contact.image) {
            self.contactImageView.image = self.contact.image;
        }
        [UIUtil applyRoundedBorderToImageView:&_contactImageView];
        [self configureFavouritesButton];
        [self.contactInfoTableView reloadData];
    }
    [super viewWillAppear:animated];
}

#pragma mark - UITableViewDelegate

- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    return self.secureInfoHeaderView;
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    return self.secureInfoHeaderView.bounds.size.height;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger secureNumberCount = (NSInteger)self.contact.userTextPhoneNumbers.count + (NSInteger)self.contact.emails.count;
    return self.contact.notes != nil ? secureNumberCount + 1 : secureNumberCount;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    ContactDetailTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:DETAIL_TABLE_CELL_IDENTIFIER];

    if (!cell) {
        cell = [[ContactDetailTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                 reuseIdentifier:DETAIL_TABLE_CELL_IDENTIFIER];
    }
        
    if ((NSUInteger)indexPath.row < self.contact.userTextPhoneNumbers.count) {
        
        PhoneNumber* phoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:self.contact.userTextPhoneNumbers[(NSUInteger)indexPath.row]];
        BOOL isSecure = [Environment.getCurrent.phoneDirectoryManager.getCurrentFilter containsPhoneNumber:phoneNumber];
        [cell configureWithPhoneNumber:phoneNumber isSecure:isSecure];
        
    } else if ((NSUInteger)indexPath.row < self.contact.userTextPhoneNumbers.count + self.contact.emails.count) {
        
        NSUInteger emailIndex = (NSUInteger)indexPath.row - self.contact.userTextPhoneNumbers.count;
        [cell configureWithEmailString:self.contact.emails[emailIndex]];
        
    } else {
        [cell configureWithNotes:self.contact.notes];
        return cell;
    }

    return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row < (NSInteger)[[self.contact userTextPhoneNumbers] count]) {

        NSString* numberString = self.contact.userTextPhoneNumbers[(NSUInteger)indexPath.row];
        PhoneNumber* number = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:numberString];
        BOOL sercureNumberTapped = [self phoneNumberIsSecure:number];
         
        if (sercureNumberTapped) {
            [self startSecureCallWithNumber:number];
        } else {
            [self openPhoneAppWithPhoneNumber:number];
        }
        
    } else if ((NSUInteger)indexPath.row < self.contact.userTextPhoneNumbers.count + self.contact.emails.count) {
        NSUInteger emailIndex = (NSUInteger)indexPath.row - self.contact.userTextPhoneNumbers.count;
        [self openEmailAppWithEmail:self.contact.emails[emailIndex]];
    }
}

- (CGFloat)tableView:(UITableView*)tableView heightForRowAtIndexPath:(NSIndexPath*)indexPath {

    BOOL cellNeedsHeightForText = indexPath.row == (NSInteger)[[self.contact userTextPhoneNumbers] count] + (NSInteger)[[self.contact emails] count];

    if (cellNeedsHeightForText) {
        CGSize size = [self.contact.notes sizeWithAttributes:@{NSFontAttributeName:[UIUtil helveticaRegularWithSize:17]}];
        return size.height + CONTACT_DETAIL_CELL_HEIGHT;
    } else {
        return CONTACT_DETAIL_CELL_HEIGHT;
    }
}

- (void)favouriteButtonTapped {
    [Environment.getCurrent.contactsManager toggleFavourite:self.contact];
    [self configureFavouritesButton];
}

- (void)configureFavouritesButton {
    if (self.contact.isFavourite) {
        UIImage* favouriteImage = [UIImage imageNamed:FAVOURITE_TRUE_ICON_NAME];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:favouriteImage
                                                                                  style:UIBarButtonItemStylePlain
                                                                                 target:self
                                                                                 action:@selector(favouriteButtonTapped)];
        self.navigationItem.rightBarButtonItem.tintColor = UIColor.yellowColor;
    } else {
        UIImage* favouriteImage = [UIImage imageNamed:FAVOURITE_FALSE_ICON_NAME];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:favouriteImage
                                                                                  style:UIBarButtonItemStylePlain
                                                                                 target:self
                                                                                 action:@selector(favouriteButtonTapped)];
        self.navigationItem.rightBarButtonItem.tintColor = UIColor.whiteColor;
    }
}

- (void)openPhoneAppWithPhoneNumber:(PhoneNumber*)phoneNumber {
    if (phoneNumber) {
        [UIApplication.sharedApplication openURL:phoneNumber.toSystemDialerURL];
    }
}

- (void)openEmailAppWithEmail:(NSString*)email {
    NSString* mailURL = [NSString stringWithFormat:@"%@%@",MAIL_URL_PREFIX, email];
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:mailURL]];
}

- (void)startSecureCallWithNumber:(PhoneNumber*)number {
    [Environment.phoneManager initiateOutgoingCallToContact:self.contact atRemoteNumber:number];
}

- (BOOL)phoneNumberIsSecure:(PhoneNumber*)phoneNumber {
    PhoneNumberDirectoryFilter* directory = Environment.getCurrent.phoneDirectoryManager.getCurrentFilter;
    return phoneNumber != nil && [directory containsPhoneNumber:phoneNumber];
}

@end
