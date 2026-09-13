//
//  KayokoCustomJumpEditorViewController.m
//  Kayoko
//

#import "KayokoCustomJumpEditorViewController.h"
#import "KayokoCustomJump.h"
#import "KayokoKeyboardAvoidanceCoordinator.h"

@interface KayokoCustomJumpEditorViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property(nonatomic, strong) KayokoCustomJump *jump;
@property(nonatomic, strong) NSBundle *localizationBundle;
@property(nonatomic, assign, getter=isImageAction) BOOL imageAction;
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) UITextField *titleTextField;
@property(nonatomic, strong) UITextField *linkTextField;
@property(nonatomic, strong) UITextField *iconTextField;
@property(nonatomic, strong) KayokoKeyboardAvoidanceCoordinator *keyboardAvoidanceCoordinator;
@property(nonatomic, assign) BOOL didFocusTitleTextFieldInitially;
@end

@implementation KayokoCustomJumpEditorViewController

- (instancetype)initWithJump:(KayokoCustomJump *)jump localizationBundle:(NSBundle *)localizationBundle {
    return [self initWithJump:jump localizationBundle:localizationBundle isImageAction:NO];
}

- (instancetype)initWithJump:(KayokoCustomJump *)jump
            localizationBundle:(NSBundle *)localizationBundle
                isImageAction:(BOOL)isImageAction {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _jump = [jump copy];
        _localizationBundle = localizationBundle ?: [NSBundle mainBundle];
        _imageAction = isImageAction;
        [self setModalPresentationStyle:UIModalPresentationPageSheet];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[self view] setBackgroundColor:[UIColor systemGroupedBackgroundColor]];
    NSString *titleKey = [self isImageAction] ? @"Edit Image Action" : @"Edit Custom Jump";
    [self setTitle:[self localizedStringForKey:titleKey]];

    [[self navigationItem] setLeftBarButtonItem:[[UIBarButtonItem alloc] initWithTitle:[self localizedStringForKey:@"Cancel"]
                                                                                   style:UIBarButtonItemStylePlain
                                                                                  target:self
                                                                                  action:@selector(cancelEditing)]];
    [[self navigationItem] setRightBarButtonItem:[[UIBarButtonItem alloc] initWithTitle:[self localizedStringForKey:@"Done"]
                                                                                    style:UIBarButtonItemStyleDone
                                                                                   target:self
                                                                                   action:@selector(finishEditing)]];

    [self configureTableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[self keyboardAvoidanceCoordinator] startObserving];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if ([self didFocusTitleTextFieldInitially]) {
        return;
    }
    [self setDidFocusTitleTextFieldInitially:YES];
    [[self titleTextField] becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[self keyboardAvoidanceCoordinator] stopObservingAndRestoreInsets];
}

- (void)configureTableView {
    _titleTextField = [[UITextField alloc] init];
    [_titleTextField setText:[[self jump] title]];
    [_titleTextField setReturnKeyType:UIReturnKeyNext];
    [_titleTextField setDelegate:self];
    [_titleTextField setTextAlignment:NSTextAlignmentRight];

    _linkTextField = [[UITextField alloc] init];
    [_linkTextField setText:[[self jump] link]];
    [_linkTextField setReturnKeyType:UIReturnKeyNext];
    [_linkTextField setDelegate:self];
    [_linkTextField setTextAlignment:NSTextAlignmentRight];
    [_linkTextField setKeyboardType:UIKeyboardTypeURL];
    [_linkTextField setAutocapitalizationType:UITextAutocapitalizationTypeNone];
    [_linkTextField setAutocorrectionType:UITextAutocorrectionTypeNo];

    _iconTextField = [[UITextField alloc] init];
    [_iconTextField setText:[[self jump] icon]];
    [_iconTextField setReturnKeyType:UIReturnKeyDone];
    [_iconTextField setDelegate:self];
    [_iconTextField setTextAlignment:NSTextAlignmentRight];
    [_iconTextField setKeyboardType:UIKeyboardTypeASCIICapable];
    [_iconTextField setAutocapitalizationType:UITextAutocapitalizationTypeNone];
    [_iconTextField setAutocorrectionType:UITextAutocorrectionTypeNo];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    [_tableView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [_tableView setDataSource:self];
    [_tableView setDelegate:self];
    [_tableView setKeyboardDismissMode:UIScrollViewKeyboardDismissModeInteractive];
    [[self view] addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [[_tableView topAnchor] constraintEqualToAnchor:[[self view] topAnchor]],
        [[_tableView leadingAnchor] constraintEqualToAnchor:[[self view] leadingAnchor]],
        [[_tableView trailingAnchor] constraintEqualToAnchor:[[self view] trailingAnchor]],
        [[_tableView bottomAnchor] constraintEqualToAnchor:[[self view] bottomAnchor]]
    ]];
    _keyboardAvoidanceCoordinator = [[KayokoKeyboardAvoidanceCoordinator alloc] initWithView:[self view]
                                                                                     scrollView:_tableView];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == [self titleTextField]) {
        [[self linkTextField] becomeFirstResponder];
    } else if (textField == [self linkTextField]) {
        [[self iconTextField] becomeFirstResponder];
    } else {
        [textField resignFirstResponder];
    }
    return YES;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return 3;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const reuseIdentifier = @"KayokoCustomJumpEditorCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
        [cell setSelectionStyle:UITableViewCellSelectionStyleNone];
    }

    [[cell textLabel] setTextColor:[UIColor labelColor]];
    [cell setAccessoryView:nil];
    if ([indexPath row] == 0) {
        [[cell textLabel] setText:[self localizedStringForKey:@"Title"]];
        [[self titleTextField] setFrame:CGRectMake(0.0, 0.0, 220.0, 36.0)];
        [cell setAccessoryView:[self titleTextField]];
    } else if ([indexPath row] == 1) {
        [[cell textLabel] setText:[self localizedStringForKey:@"Jump Link"]];
        [[self linkTextField] setFrame:CGRectMake(0.0, 0.0, 220.0, 36.0)];
        [cell setAccessoryView:[self linkTextField]];
    } else {
        [[cell textLabel] setText:[self localizedStringForKey:@"Icon"]];
        [[self iconTextField] setFrame:CGRectMake(0.0, 0.0, 220.0, 36.0)];
        [cell setAccessoryView:[self iconTextField]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if ([indexPath row] == 0) {
        [[self titleTextField] becomeFirstResponder];
    } else if ([indexPath row] == 1) {
        [[self linkTextField] becomeFirstResponder];
    } else {
        [[self iconTextField] becomeFirstResponder];
    }
}

- (void)cancelEditing {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)finishEditing {
    NSString *title = [[[self titleTextField] text]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *link = [[[self linkTextField] text]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *icon = [[[self iconTextField] text]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([title length] == 0) {
        title = [self localizedStringForKey:@"Untitled"];
    }

    KayokoCustomJump *updatedJump =
        [[KayokoCustomJump alloc] initWithUUID:[[self jump] uuid] title:title link:link icon:icon];
    void (^completionHandler)(KayokoCustomJump *) = [self completionHandler];
    [self dismissViewControllerAnimated:YES
                             completion:^{
                               if (completionHandler) {
                                   completionHandler(updatedJump);
                               }
                             }];
}

- (NSString *)localizedStringForKey:(NSString *)key {
    return [[self localizationBundle] localizedStringForKey:key value:key table:@"CustomJumps"] ?: key;
}

@end
