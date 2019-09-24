//
//  NAudioPlayer.h
//  NAudioPlayer
//
//  Created by 泽娄 on 2019/9/22.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NAudioPlayer : NSObject

- (instancetype)initWithFilePath:(NSString *)filePath;

- (void)play;

- (void)pause;

- (void)stop;

- (void)playWithUrlString:(NSString *)urlString;

@end

NS_ASSUME_NONNULL_END
