//
//  NAudioFileStream.h
//  NAudioFileStream
//
//  Created by 泽娄 on 2019/9/21.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

NS_ASSUME_NONNULL_BEGIN

@class NAudioFileStream;

@protocol NAudioFileStreamDelegate <NSObject>
@optional
/// 准备解析音频数据帧
- (void)audioStream_readyToProducePacketsWithAudioFileStream:(NAudioFileStream *)audioFileStream;

@required
///// 解析音频数据帧
//- (void)audioStream_packetsWithAudioFileStream:(NAudioFileStream *)audioFileStream
//                                          audioDatas:(NSArray *)audioDatas;


- (void)audioStream_packetsWithAudioFileStream:(NAudioFileStream *)audioFileStream
                                          data:(NSData *)data
                                 inNumberBytes:(UInt32)inNumberBytes
                               inNumberPackets:(UInt32)inNumberPackets
                          inPacketDescrrptions:(AudioStreamPacketDescription *)inPacketDescrrptions;

@end

@interface NAudioFileStream : NSObject

@property (nonatomic, assign, nullable) id<NAudioFileStreamDelegate>delegate;

/// 该属性指明了音频数据的格式信息，返回的数据是一个AudioStreamBasicDescription结构
@property (nonatomic, assign, readonly) AudioStreamBasicDescription audioStreamBasicDescription;

@property (nonatomic, assign, readonly) NSTimeInterval duration; /// 时长

- (instancetype)initWithFilePath:(NSString *)path fileLength:(NSInteger )fileLength;

- (void)parseData:(NSData *)data;

/// 拖动进度条，需要到几分几秒，而我们实际上操作的是文件，即寻址到第几个字节开始播放音频数据
- (void)seekToTime:(NSTimeInterval *)newSeekTime;

@end

NS_ASSUME_NONNULL_END