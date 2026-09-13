//
//  KayokoQuickAction.m
//  Kayoko
//

#import "KayokoQuickAction.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <roothide.h>

static NSString *const kKayokoTextActionStorePath = @"/var/mobile/Library/com.lindo.kayoko/custom-jumps-v1.plist";
static NSString *const kKayokoImageActionStorePath = @"/var/mobile/Library/com.lindo.kayoko/image-actions-v1.plist";

static NSString *const kKayokoQuickActionDefaultIconName = @"link";

// Declared locally: FBSSystemService, FBSOpenApplicationService, and LSApplicationWorkspace are not in the SDK.
// The FBSSystemService signature matches the entry LLVM debugserver uses to launch apps on device.
@interface FBSSystemService : NSObject
+ (instancetype)sharedService;
+ (instancetype)sharedInstance;
- (void)openApplication:(NSString *)bundleIdentifier
                options:(NSDictionary<NSString *, id> *)options
             withResult:(void (^)(NSError *error))resultHandler;
@end

@interface FBSOpenApplicationService : NSObject
+ (instancetype)sharedInstance;
- (void)openApplication:(NSString *)bundleIdentifier
                options:(NSDictionary<NSString *, id> *)options
     withResultHandler:(void (^)(BOOL success, NSError *error))resultHandler;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleIdentifier;
@end

@implementation KayokoQuickAction

+ (NSArray<NSDictionary<NSString *, id> *> *)actionsForKind:(KayokoQuickActionKind)kind {
    NSString *path = kind == KayokoQuickActionKindImage ? kKayokoImageActionStorePath : kKayokoTextActionStorePath;
    NSData *data = [NSData dataWithContentsOfFile:jbroot(path)];
    if (!data) {
        return @[];
    }

    NSPropertyListFormat format = NSPropertyListXMLFormat_v1_0;
    id propertyList = [NSPropertyListSerialization propertyListWithData:data
                                                                options:NSPropertyListImmutable
                                                                 format:&format
                                                                  error:nil];
    if (![propertyList isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *actions = [[NSMutableArray alloc] init];
    for (id item in (NSArray *)propertyList) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *title = item[@"title"];
        NSString *link = item[@"link"];
        NSString *icon = item[@"icon"];
        if (![title isKindOfClass:[NSString class]] || ![link isKindOfClass:[NSString class]] ||
            [title length] == 0) {
            continue;
        }
        if (![icon isKindOfClass:[NSString class]] || [icon length] == 0) {
            icon = kKayokoQuickActionDefaultIconName;
        }
        [actions addObject:@{ @"title" : title, @"link" : link, @"icon" : icon }];
    }
    return [actions copy];
}

+ (void)openAction:(NSDictionary<NSString *, id> *)action
             input:(NSString *)input
 completionHandler:(void (^)(BOOL success))completionHandler {
    NSString *link = [self resolvedLinkForAction:action input:input];
    if ([link length] == 0) {
        [self finishOpening:completionHandler success:NO];
        return;
    }

    NSURL *URL = [NSURL URLWithString:link];
    if (URL && ![URL scheme] && [self looksLikeBundleIdentifier:link]) {
        [self openApplicationWithBundleIdentifier:link completionHandler:completionHandler];
        return;
    }
    if (!URL) {
        [self finishOpening:completionHandler success:NO];
        return;
    }

    [[UIApplication sharedApplication] openURL:URL
                                       options:@{}
                             completionHandler:^(BOOL success) {
                               [self finishOpening:completionHandler success:success];
                             }];
}

#pragma mark - Private

+ (NSString *)resolvedLinkForAction:(NSDictionary<NSString *, id> *)action input:(NSString *)input {
    NSString *link = [action isKindOfClass:[NSDictionary class]] ? action[@"link"] : nil;
    if (![link isKindOfClass:[NSString class]]) {
        return @"";
    }

    NSString *encodedInput = [self percentEncodedInput:input ?: @""];
    for (NSString *placeholder in @[ @"$$$", @"@@@" ]) {
        link = [link stringByReplacingOccurrencesOfString:placeholder withString:encodedInput];
    }
    return link;
}

+ (BOOL)looksLikeBundleIdentifier:(NSString *)string {
    if ([string rangeOfString:@"."].location == NSNotFound) {
        return NO;
    }
    NSMutableCharacterSet *invalidCharacters =
        [[[NSCharacterSet alphanumericCharacterSet] invertedSet] mutableCopy];
    [invalidCharacters removeCharactersInString:@"-."];
    return [string rangeOfCharacterFromSet:invalidCharacters].location == NSNotFound;
}

+ (void)openApplicationWithBundleIdentifier:(NSString *)bundleIdentifier
                          completionHandler:(void (^)(BOOL success))completionHandler {
    id serviceClass = objc_getClass("FBSSystemService");
    id service = nil;
    if ([serviceClass respondsToSelector:@selector(sharedService)]) {
        service = [serviceClass sharedService];
    } else if ([serviceClass respondsToSelector:@selector(sharedInstance)]) {
        service = [serviceClass sharedInstance];
    }
    if (service &&
        [service respondsToSelector:@selector(openApplication:options:withResult:)]) {
        [service openApplication:bundleIdentifier
                         options:@{}
                      withResult:^(NSError *error) {
                        // Success is the absence of an NSError. Older payloads were not always
                        // NSError, so anything non-nil and non-NSError still counts as success.
                        if (error == nil || ![error isKindOfClass:[NSError class]]) {
                            [self finishOpening:completionHandler success:YES];
                            return;
                        }
                        [self openApplicationWithCompatibilityPath:bundleIdentifier completionHandler:completionHandler];
                      }];
        return;
    }

    [self openApplicationWithCompatibilityPath:bundleIdentifier completionHandler:completionHandler];
}

+ (void)openApplicationWithCompatibilityPath:(NSString *)bundleIdentifier
                           completionHandler:(void (^)(BOOL success))completionHandler {
    id openServiceClass = objc_getClass("FBSOpenApplicationService");
    id openService = [openServiceClass respondsToSelector:@selector(sharedInstance)] ? [openServiceClass sharedInstance] : nil;
    if (openService &&
        [openService respondsToSelector:@selector(openApplication:options:withResultHandler:)]) {
        [openService openApplication:bundleIdentifier
                             options:@{}
                   withResultHandler:^(BOOL success, NSError *error) {
                     (void)error;
                     [self finishOpening:completionHandler success:success];
                   }];
        return;
    }

    id workspaceClass = objc_getClass("LSApplicationWorkspace");
    id workspace = [workspaceClass respondsToSelector:@selector(defaultWorkspace)] ? [workspaceClass defaultWorkspace] : nil;
    if (workspace && [workspace respondsToSelector:@selector(openApplicationWithBundleID:)]) {
        BOOL success = [workspace openApplicationWithBundleID:bundleIdentifier];
        [self finishOpening:completionHandler success:success];
        return;
    }

    [self finishOpening:completionHandler success:NO];
}

+ (void)finishOpening:(void (^)(BOOL success))completionHandler success:(BOOL)success {
    if (!completionHandler) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      completionHandler(success);
    });
}

+ (NSString *)percentEncodedInput:(NSString *)input {
    NSMutableCharacterSet *allowedCharacters = [[NSCharacterSet alphanumericCharacterSet] mutableCopy];
    [allowedCharacters addCharactersInString:@"-._~"];
    return [input stringByAddingPercentEncodingWithAllowedCharacters:allowedCharacters] ?: @"";
}

@end
