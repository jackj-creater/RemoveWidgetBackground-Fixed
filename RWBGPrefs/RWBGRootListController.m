#import <Foundation/Foundation.h>
#import <Preferences/PSSpecifier.h>
#import <stdlib.h>
#import <sys/sysctl.h>

#import "RWBGRootListController.h"

void RWBGEnumerateProcessesUsingBlock(void (^enumerator)(pid_t pid, NSString *executablePath, BOOL *stop)) {
    static int kMaximumArgumentSize = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      size_t valSize = sizeof(kMaximumArgumentSize);
      if (sysctl((int[]){CTL_KERN, KERN_ARGMAX}, 2, &kMaximumArgumentSize, &valSize, NULL, 0) < 0) {
          perror("sysctl argument size");
          kMaximumArgumentSize = 4096;
      }
    });

    size_t procInfoLength = 0;
    if (sysctl((int[]){CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0}, 3, NULL, &procInfoLength, NULL, 0) < 0) {
        return;
    }

    static struct kinfo_proc *procInfo = NULL;
    procInfo = (struct kinfo_proc *)realloc(procInfo, procInfoLength + 1);
    if (!procInfo) {
        return;
    }

    bzero(procInfo, procInfoLength + 1);
    if (sysctl((int[]){CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0}, 3, procInfo, &procInfoLength, NULL, 0) < 0) {
        return;
    }

    static char *argBuffer = NULL;
    int procInfoCnt = (int)(procInfoLength / sizeof(struct kinfo_proc));
    for (int i = 0; i < procInfoCnt; i++) {

        pid_t pid = procInfo[i].kp_proc.p_pid;
        if (pid <= 1) {
            continue;
        }

        size_t argSize = kMaximumArgumentSize;
        if (sysctl((int[]){CTL_KERN, KERN_PROCARGS2, pid, 0}, 3, NULL, &argSize, NULL, 0) < 0) {
            continue;
        }

        argBuffer = (char *)realloc(argBuffer, argSize + 1);
        if (!argBuffer) {
            continue;
        }

        bzero(argBuffer, argSize + 1);
        if (sysctl((int[]){CTL_KERN, KERN_PROCARGS2, pid, 0}, 3, argBuffer, &argSize, NULL, 0) < 0) {
            continue;
        }

        BOOL stop = NO;
        @autoreleasepool {
            enumerator(pid, [NSString stringWithUTF8String:(argBuffer + sizeof(int))], &stop);
        }

        if (stop) {
            break;
        }
    }
}

void RWBGKillAll(NSString *processName, BOOL softly) {
    RWBGEnumerateProcessesUsingBlock(^(pid_t pid, NSString *executablePath, BOOL *stop) {
      if ([executablePath.lastPathComponent isEqualToString:processName]) {
          if (softly) {
              kill(pid, SIGTERM);
          } else {
              kill(pid, SIGKILL);
          }
      }
    });
}

void RWBGBatchKillAll(NSArray<NSString *> *processNames, BOOL softly) {
    RWBGEnumerateProcessesUsingBlock(^(pid_t pid, NSString *executablePath, BOOL *stop) {
      if ([processNames containsObject:executablePath.lastPathComponent]) {
          if (softly) {
              kill(pid, SIGTERM);
          } else {
              kill(pid, SIGKILL);
          }
      }
    });
}

@interface LSPlugInKitProxy : NSObject
@property(nonatomic, readonly, copy) NSString *pluginIdentifier;
@end

@interface LSApplicationProxy : NSObject
@property(nonatomic, readonly) NSArray<LSPlugInKitProxy *> *plugInKitPlugins;
+ (LSApplicationProxy *)applicationProxyForIdentifier:(NSString *)bundleIdentifier;
@end

@implementation RWBGRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    if ([specifier.properties[@"key"] isEqualToString:@"AppIdentifiers"]) {
        NSAssert([value isKindOfClass:[NSArray class]], @"value is not an array");

        NSMutableArray<NSString *> *plugInIdentifiers = [NSMutableArray new];
        for (NSString *bundleIdentifier in value) {
            LSApplicationProxy *appProxy = [LSApplicationProxy applicationProxyForIdentifier:bundleIdentifier];
            for (LSPlugInKitProxy *plugInProxy in appProxy.plugInKitPlugins) {
                if (plugInProxy.pluginIdentifier)
                    [plugInIdentifiers addObject:plugInProxy.pluginIdentifier];
            }
        }

        PSSpecifier *stubSpecifier = [PSSpecifier preferenceSpecifierNamed:@"WidgetBundleIdentifiers"
                                                                    target:self
                                                                       set:@selector(setPreferenceValue:specifier:)
                                                                       get:@selector(readPreferenceValue:)
                                                                    detail:nil
                                                                      cell:PSLinkListCell
                                                                      edit:nil];

        [stubSpecifier setProperty:@"WidgetBundleIdentifiers" forKey:@"key"];
        [stubSpecifier setProperty:@"com.82flex.removewidgetbgprefs" forKey:@"defaults"];
        [stubSpecifier setProperty:@"com.82flex.removewidgetbgprefs/saved" forKey:@"PostNotification"];

        [super setPreferenceValue:plugInIdentifiers specifier:stubSpecifier];
    }
}

- (void)respring {
    RWBGBatchKillAll(
        @[
            @"SpringBoard", @"chronod", @"com.apple.chrono.WidgetRenderer-Default",
            @"com.apple.chrono.WidgetRenderer-CarPlay"
        ],
        YES);
}

- (void)support {
    NSURL *url = [NSURL URLWithString:@"https://havoc.app/search/82Flex"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)recordWidgetDiagnostic {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"记录组件黑底（30 秒）"
        message:@"开始后回到桌面，点击天气或健身组件打开 App，再返回桌面。30 秒后回来点“导出诊断”。只记录视图状态，不记录组件文字或截图。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"开始" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.82flex.removewidgetbg/diagnostic-begin"), NULL, NULL, YES);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)exportWidgetDiagnostic {
    NSString *path = @"/var/mobile/Library/Logs/RemoveWidgetBackground-diagnostic.txt";
    NSError *error = nil;
    NSString *report = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    BOOL complete = [report containsString:@"Capture complete"];
    if (!report || !complete) {
        NSString *message = report ? @"还在记录，请等待 30 秒后再导出。若一直如此，请确认插件已启用，并使用本页“注销以应用更改”后重新记录。"
            : @"未找到诊断文件。请确认插件已启用，安装后注销桌面一次，再点“记录组件黑底”。";
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"诊断尚未完成"
            message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSString *exportPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"RemoveWidgetBackground-diagnostic.txt"];
    if (![report writeToFile:exportPath atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出失败"
            message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIActivityViewController *sheet = [[UIActivityViewController alloc]
        initWithActivityItems:@[[NSURL fileURLWithPath:exportPath]] applicationActivities:nil];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
        CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    {
        PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
        NSString *key = [specifier propertyForKey:@"cell"];
        if ([key isEqualToString:@"PSButtonCell"]) {
            UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
            NSNumber *isDestructiveValue = [specifier propertyForKey:@"isDestructive"];
            BOOL isDestructive = [isDestructiveValue boolValue];
            cell.textLabel.textColor = isDestructive ? [UIColor systemRedColor] : [UIColor systemBlueColor];
            cell.textLabel.highlightedTextColor = isDestructive ? [UIColor systemRedColor] : [UIColor systemBlueColor];
            return cell;
        }
    }
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}

@end
