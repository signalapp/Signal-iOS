#import "ContactDetailViewController.h"
#import "ContactsManager.h"
#import "InCallViewController.h"
#import "UIUtil.h"

#define CONTACT_DETAIL_CELL_HEIGHT 49

static NSString *const DEFAULT_CONTACT_IMAGE = @"DefaultContactImage.png";
static NSString *const DETAIL_TABLE_CELL_IDENTIFIER = @"ContactDetailTableViewCell";
static NSString *const MAIL_URL_PREFIX = @"mailto://";

static NSString *const FAVOURITE_TRUE_ICON_NAME = @"favourite_true_icon";
static NSString *const FAVOURITE_FALSE_ICON_NAME = @"favourite_false_icon";

@implementation ContactDetailViewController

+ (ContactDetailViewController *)contactDetailViewControllerWithContact:(Contact *)contact {
    ContactDetailViewController *contactDetailViewController = [ContactDetailViewController new];
    contactDetailViewController->_contact = contact;
    return contactDetailViewController;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _contactInfoTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (void)viewWillAppear:(BOOL)animated {
	
    if (_contact) {
        self.navigationController.navigationBar.barTintColor = [UIUtil darkBackgroundColor];
        self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
        self.navigationController.navigationBar.translucent = NO;
        _contactNameLabel.text = _contact.fullName;
        if (_contact.image) {
            _contactImageView.image = _contact.image;
        }
        [UIUtil applyRoundedBorderToImageView:&_contactImageView];
        [self configureFavouritesButton];
        [_contactInfoTableView reloadData];
    }
    [super viewWillAppear:animated];
}

#pragma mark - UITableViewDelegate

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return _secureInfoHeaderView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return _secureInfoHeaderView.bounds.size.height;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger secureNumberCount = (NSInteger)_contact.userTextPhoneNumbers.count + (NSInteger)_contact.emails.count;
    return _contact.notes != nil ? secureNumberCount + 1 : secureNumberCount;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ContactDetailTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:DETAIL_TABLE_CELL_IDENTIFIER];

    if (!cell) {
        cell = [[ContactDetailTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                 reuseIdentifier:DETAIL_TABLE_CELL_IDENTIFIER];
    }
        
    if ((NSUInteger)indexPath.row < _contact.userTextPhoneNumbers.count) {
        
        PhoneNumber *phoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:_contact.userTextPhoneNumbers[(NSUInteger)indexPath.row]];
        BOOL isSecure = [[[[Environment getCurrent] phoneDirectoryManager] getCurrentFilter] containsPhoneNumber:phoneNumber];
        [cell configureWithPhoneNumber:phoneNumber isSecure:isSecure];
        
    } else if ((NSUInteger)indexPath.row < _contact.userTextPhoneNumbers.count + _contact.emails.count) {
        
        NSUInteger emailIndex = (NSUInteger)indexPath.row - _contact.userTextPhoneNumbers.count;
        [cell configureWithEmailString:_contact.emails[emailIndex]];
        
    } else {
        [cell configureWithNotes:_contact.notes];
        return cell;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row < (NSInteger)[[_contact userTextPhoneNumbers] count]) {

        NSString *numberString = _contact.userTextPhoneNumbers[(NSUInteger)indexPath.row];
        PhoneNumber *number = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:numberString];
        BOOL sercureNumberTapped = [self phoneNumberIsSecure:number];
         
        if (sercureNumberTapped) {
            [self startSecureCallWithNumber:number];
        } else {
            [self openPhoneAppWithPhoneNumber:number];
        }
        
    } else if ((NSUInteger)indexPath.row < _contact.userTextPhoneNumbers.count + _contact.emails.count) {
        NSUInteger emailIndex = (NSUInteger)indexPath.row - _contact.userTextPhoneNumbers.count;
        [self openEmailAppWithEmail:_contact.emails[emailIndex]];
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {

    BOOL cellNeedsHeightForText = indexPath.row == (NSInteger)[[_contact userTextPhoneNumbers] count] + (NSInteger)[[_contact emails] count];

    if (cellNeedsHeightForText) {
        CGSize size = [_contact.notes sizeWithAttributes:@{NSFontAttributeName:[UIUtil helveticaRegularWithSize:17]}];
        return size.height + CONTACT_DETAIL_CELL_HEIGHT;
    } else {
        return CONTACT_DETAIL_CELL_HEIGHT;
    }
}

- (void)favouriteButtonTapped {
    [[[Environment getCurrent] contactsManager] toggleFavourite:_contact];
    [self configureFavouritesButton];
}

- (void)configureFavouritesButton {
    if (_contact.isFavourite) {
        UIImage *favouriteImage = [UIImage imageNamed:FAVOURITE_TRUE_ICON_NAME];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:favouriteImage
                                                                                  style:UIBarButtonItemStylePlain
                                                                                 target:self
                                                                                 action:@selector(favouriteButtonTapped)];
        self.navigationItem.rightBarButtonItem.tintColor = [UIColor yellowColor];
    } else {
        UIImage *favouriteImage = [UIImage imageNamed:FAVOURITE_FALSE_ICON_NAME];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:favouriteImage
                                                                                  style:UIBarButtonItemStylePlain
                                                                                 target:self
                                                                                 action:@selector(favouriteButtonTapped)];
        self.navigationItem.rightBarButtonItem.tintColor = [UIColor whiteColor];
    }
}

- (void)openPhoneAppWithPhoneNumber:(PhoneNumber *)phoneNumber {
    if (phoneNumber) {
        [UIApplication.sharedApplication openURL:phoneNumber.toSystemDialerURL];
    }
}

- (void)openEmailAppWithEmail:(NSString *)email {
    NSString *mailURL = [NSString stringWithFormat:@"%@%@",MAIL_URL_PREFIX, email];
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:mailURL]];
}

- (void)startSecureCallWithNumber:(PhoneNumber *)number {
    [[Environment phoneManager] initiateOutgoingCallToContact:_contact atRemoteNumber:number];
}

- (BOOL)phoneNumberIsSecure:(PhoneNumber *)phoneNumber {
    PhoneNumberDirectoryFilter* directory = [[[Environment getCurrent] phoneDirectoryManager] getCurrentFilter];
    return phoneNumber != nil && [directory containsPhoneNumber:phoneNumber];
}

@end
