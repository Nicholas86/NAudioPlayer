//
//  NAudioPlayer.h
//  NAudioPlayer
//
//  Created by 泽娄 on 2019/9/22.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, NAudioPlayerStatus)
{
    NAudioPlayerStatusStopped = 0,
    NAudioPlayerStatusPlaying = 1,
    NAudioPlayerStatusWaiting = 2,
    NAudioPlayerStatusPaused = 3,
    NAudioPlayerStatusFlushing = 4,
};

NS_ASSUME_NONNULL_BEGIN

@interface NAudioPlayer : NSObject

@property (nonatomic, readonly) NAudioPlayerStatus status;

@property (nonatomic, readonly) NSTimeInterval duration; /// 总时长

- (instancetype)initWithFilePath:(NSString *)filePath;

- (void)play;

- (void)pause;

- (void)stop;

- (void)playWithUrlString:(NSString *)urlString;

@end

NS_ASSUME_NONNULL_END
