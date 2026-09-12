//
//  KayokoQuickAction.m
//  Kayoko
//

#import "KayokoQuickAction.h"

#import <roothide.h>

static NSString *const kKayokoTextActionStorePath = @"/var/mobile/Library/com.lindo.kayoko/custom-jumps-v1.plist";
static NSString *const kKayokoImageActionStorePath = @"/var/mobile/Library/com.lindo.kayoko/image-actions-v1.plist";

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
        if (![title isKindOfClass:[NSString class]] || ![link isKindOfClass:[NSString class]] ||
            [title length] == 0) {
            continue;
        }
        [actions addObject:@{ @"title" : title, @"link" : link }];
    }
    return [actions copy];
}

+ (NSURL *)URLForAction:(NSDictionary<NSString *, id> *)action input:(NSString *)input {
    NSString *link = action[@"link"];
    if (![link isKindOfClass:[NSString class]]) {
        return nil;
    }

    NSString *encodedInput = [self percentEncodedInput:input ?: @""];
    for (NSString *placeholder in @[ @"$$$", @"@@@" ]) {
        link = [link stringByReplacingOccurrencesOfString:placeholder withString:encodedInput];
    }
    if ([link length] == 0) {
        return nil;
    }
    return [NSURL URLWithString:link];
}

+ (NSString *)percentEncodedInput:(NSString *)input {
    NSMutableCharacterSet *allowedCharacters = [[NSCharacterSet alphanumericCharacterSet] mutableCopy];
    [allowedCharacters addCharactersInString:@"-._~"];
    return [input stringByAddingPercentEncodingWithAllowedCharacters:allowedCharacters] ?: @"";
}

@end
