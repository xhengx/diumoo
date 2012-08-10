//
//  DMService.m
//  diumoo
//
//  Created by Shanzi on 12-8-3.
//
//

#import "DMService.h"
#import "DMPlayRecordHandler.h"
#import "NSData+AESCrypt.h"
#import "CJSONDeserializer.h"

#define DM_SONG_PREFIX @"dm://song?key="
#define DOUBAN_SHARE_PREFIX @"http://douban.fm/?start="
#define NOTIFICATION_URL @"http://diumoo-notification.herokuapp.com/notification"
//#define NOTIFICATION_URL @"http://diumoo-notification.hero/notification"

#define APP_TYPE_PRO 1
#define APP_TYPE_LITE (1<<1)
#define APP_TYPE_TEST (1<<2)
#define CURRENT_APP_TYPE APP_TYPE_TEST

static NSOperationQueue* serviceQueue;

@implementation DMService

+(NSOperationQueue*) serviceQueue
{
    if (serviceQueue) {
        return serviceQueue;
    }
    else{
        serviceQueue= [[NSOperationQueue alloc] init];
        return serviceQueue;
    }
}

+(void)performOnServiceQueue:(void(^)(void))block
{
    [[DMService serviceQueue] addOperationWithBlock:block];
}

+(void)performOnMainQueue:(void(^)(void))block
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:block];
}

//+(void)registerSongWith:(NSString *)sid :(NSString *)ssid :(NSString *)aid
//{
//    if (sid && ssid && aid) {
//        NSString* registerString = [NSString stringWithFormat:@"sid=%@&ssid=%@&aid=%@",sid,ssid,aid];
//        NSData* stringData = [registerString dataUsingEncoding:NSUTF8StringEncoding];
//        NSData* crypted = [stringData AES256EncryptWithKey:SERVICE_KEY];
//        NSString* base64String = [crypted base64EncodedString];
//        NSString* serviceUrlString = [REGISTER_SONG_SERVICE_URL stringByAppendingFormat:@"?key=%@",base64String];
//        NSURL* url = [NSURL URLWithString:serviceUrlString];
//        NSURLRequest* request = [NSURLRequest requestWithURL:url cachePolicy:NSURLCacheStorageNotAllowed
//                                             timeoutInterval:3.0];
//        [NSURLConnection sendAsynchronousRequest:request
//                                           queue:[DMService serviceQueue]
//                               completionHandler:^(NSURLResponse *r, NSData *d, NSError *e) {
//                                   if (e == NULL) {
//                                       DMLog(@"register success");
//                                   }
//                                   else
//                                   {
//                                       DMLog(@"register failed, error = %@",e);
//                                   }
//                               }];
//    }
//}

+(NSString*) cleanStartAttribute:(NSString*)start
{
    DMLog(@"clean start %@",start);
    NSArray* startComponents = [start componentsSeparatedByString:@"g"];
    if ([startComponents count]>2) {
        if ([[startComponents objectAtIndex:1] length] == 4) {
            return [NSString stringWithFormat:@"%@g%@g",
                    [startComponents objectAtIndex:0],
                    [startComponents objectAtIndex:1]
                    ];
        }
    }
    return nil;
}

+(BOOL)openDiumooLink:(NSString *)string
{
    NSString* start = nil;
    NSString* type = nil;
    
    if ([string hasPrefix:DM_SONG_PREFIX]) {
        start = [string stringByReplacingOccurrencesOfString:DM_SONG_PREFIX
                                                  withString:@""];
        start = [self cleanStartAttribute:start];
        if (start != nil) {
            type = @"song";
        }
        
    }
    else if([string hasPrefix:DOUBAN_SHARE_PREFIX])
    {
        start = [string stringByReplacingOccurrencesOfString:DOUBAN_SHARE_PREFIX
                                                  withString:@""];
        NSArray* components = [start componentsSeparatedByString:@"&"];
        if ([components count]) {
            start =[self cleanStartAttribute:start];
            if (start) {
                type = @"song";
            }
        }
    }
    
    if (type != nil) {
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"playspecial"
                                                            object:nil
                                                          userInfo:@{
         @"type" : @"song",
         @"start" : start
         }
         ];
        
        return YES;
    }
    else
    {
        NSRunCriticalAlertPanel(@"打开URL失败",
                                @"打开URL失败，您输入了非法的URL地址。目前仅支持 diumoo Link 和豆瓣分享连接(暂不支持短网址)。",
                                @"知道了", nil, nil);
        return NO;
    }
}

+(void)importRecordOperation
{
    
    NSOpenPanel* openpanel = [NSOpenPanel openPanel];
    [openpanel setCanChooseDirectories:NO];
    [openpanel setAllowsMultipleSelection:NO];
    [openpanel setAllowedFileTypes:@[@"dmrecord"]];
    [openpanel setTitle:@"导入播放记录"];
    [openpanel setPrompt:@"导入"];
    if ([openpanel runModal] == NSOKButton) {
        NSURL* url = [[openpanel URLs] objectAtIndex:0];
        [DMService importRecordOperationWithFilePath:url];
        
    }
}

+(void)importRecordOperationWithFilePath:(NSURL *)fp
{
    [DMService performOnServiceQueue:^{
        
        
        NSArray* array= nil;
        array = [NSArray arrayWithContentsOfURL:fp];
        if (array) {
            NSInteger errorcount=0;
            NSInteger finished = 0;
            DMPlayRecordHandler * handler = [DMPlayRecordHandler sharedRecordHandler];
            for (NSDictionary* song in array) {
                
                if(![handler addRecordWithDict:song]){
                    errorcount += 1;
                }
                else finished +=1;
            }
            if (finished> 0) {
                [handler save];
                NSString* summary = [NSString stringWithFormat:@"成功导入了 %ld 个歌曲记录，失败 %ld 个。",
                                     finished,errorcount];
                [DMService performOnMainQueue:^{
                    NSRunInformationalAlertPanel(@"导出播放记录结束", summary, @"OK", nil, nil);
                }];
                
                return;
            }
        }
        
        [DMService performOnMainQueue:^{
            NSRunCriticalAlertPanel(@"导入失败",
                                    @"导入播放记录失败，您试图导入的文件类型不正确或者文件已损坏。",
                                    @"知道了", nil, nil);
        }];
        
    }];
}

+(void) exportRecordOperation
{
    
    NSSavePanel* savepanel = [NSSavePanel savePanel];
    [savepanel setAllowedFileTypes:@[@"dmrecord"]];
    [savepanel setTitle:@"导出播放记录"];
    [savepanel setPrompt:@"导出"];
    if ([savepanel runModal] == NSOKButton) {
        NSURL* url = [savepanel URL];
        [DMService performOnMainQueue:^{
            
            NSArray* songs = [[DMPlayRecordHandler sharedRecordHandler] allSongs];
            if (songs) {
                NSInteger count = [songs count] + 10;
                NSInteger finished = 0;
                NSMutableArray* outarray = [[NSMutableArray alloc] initWithCapacity:count];
                
                for (NSManagedObject* song in songs) {
                    [outarray addObject:
                     @{
                     @"sid":[song valueForKey:@"sid"],
                     @"ssid":[song valueForKey:@"ssid"],
                     @"aid":[song valueForKey:@"aid"],
                     @"albumtitle":[song valueForKey:@"albumtitle"],
                     @"title":[song valueForKey:@"title"],
                     @"url":[song valueForKey:@"url"],
                     @"picture":[song valueForKey:@"picture"],
                     @"artist":[song valueForKey:@"artist"],
                     @"date":[song valueForKey:@"date"],
                     @"rating_avg":[song valueForKey:@"rating_avg"]
                     }
                     ];
                    finished += 1;
                }
                [outarray writeToURL:url atomically:YES];
                
                NSString* summary = [NSString stringWithFormat:@"成功导出 %ld 首歌曲的播放记录。",finished];
                [DMService performOnMainQueue:^{
                    NSRunInformationalAlertPanel(@"导出歌曲记录结束", summary, @"OK", nil, nil);
                }];
                
                
            }
        }];
    }
}



+(void) showDMNotification
{
    NSInteger current_id = [[[NSUserDefaults standardUserDefaults]
                             valueForKey:@"notificationID"]integerValue];
    
    NSDictionary* bundleinfo = [[NSBundle mainBundle] infoDictionary];
    NSString* version=[bundleinfo objectForKey:@"CFBundleVersion"];
    
    NSString* urlstring = [NSString stringWithFormat:@"%@?f=%d&v=%@&d=%ld",
                           NOTIFICATION_URL,CURRENT_APP_TYPE,version,current_id];
    NSLog(@"%@",urlstring);
    NSURL* url = [NSURL URLWithString:urlstring];
    NSURLRequest* request = nil;
    request = [NSURLRequest requestWithURL:url
                               cachePolicy:NSURLCacheStorageAllowed
                           timeoutInterval:10.0];
    
    [NSURLConnection sendAsynchronousRequest:request
                                       queue:[DMService serviceQueue]
                           completionHandler:^(NSURLResponse *r, NSData *d, NSError *e)
     {
         if (e==NULL) {
             NSDictionary * dict = [[CJSONDeserializer deserializer] deserializeAsDictionary:d error:&e];
             if (e==NULL) {
                 if([dict[@"nomsg"] boolValue]) return;
                 
                 NSString* title = dict[@"title"];
                 NSString* content = dict[@"content"];
                 NSString* referenceURL = dict[@"url"];
                 NSInteger _id = [dict[@"id"] integerValue];
                 BOOL force_open = [dict[@"can_cancel"] boolValue];
                 
                 
                 
                 [[NSUserDefaults standardUserDefaults]
                  setValue:@(_id) forKey:@"notificationID"
                  ];
                 
                 [DMService performOnMainQueue:
                  ^{
                      NSInteger rvalue;
                      
                      if (force_open && referenceURL) {
                          rvalue = NSRunInformationalAlertPanel(title, content,
                                                                @"查看详细", nil,
                                                                nil);
                      }
                      else
                      {
                          rvalue = NSRunInformationalAlertPanel(title, content,
                                                                @"查看详细", @"关闭", nil);
                      }
                      
                      if(rvalue == NSAlertDefaultReturn){
                          NSURL* url = [NSURL URLWithString:referenceURL];
                          [[NSWorkspace sharedWorkspace] openURL:url];
                      }
                      
                      
                  }];
                 
             }
             
         }
     }];
}

@end