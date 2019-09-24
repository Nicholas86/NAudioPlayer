//
//  NAudioPlayer.m
//  NAudioPlayer
//
//  Created by 泽娄 on 2019/9/22.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import "NAudioPlayer.h"
#import "NAudioFileStream.h"
#import "NAudioQueue.h"
#import "NAudioBuffer.h"
#import "NAudioSession.h"

#define kAudioFileBufferSize 2048   //文件读取数据的缓冲区大小

@interface NAudioPlayer ()<NAudioFileStreamDelegate>{
    NAudioBuffer *_buffer;
    NSThread *_thread;
    NSTimer *_timer;
    
    BOOL _isFileStreamExisted;
    NSInteger _fileLength;        // Length of the file in bytes
}

@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, strong) NAudioFileStream *audioFileStream;
@property (nonatomic, strong) NAudioQueue *audioQueue;

@property (nonatomic, strong) NSFileHandle *audioFileHandle;
@property (nonatomic, strong) NSData *audioFileData; // 每次读取到的文件数据
@end

@implementation NAudioPlayer

- (instancetype)initWithFilePath:(NSString *)filePath
{
    self = [super init];
    if (self) {
        _isFileStreamExisted = NO;
        self.filePath = filePath;
        self.audioFileHandle = [NSFileHandle fileHandleForReadingAtPath:filePath];
        _fileLength = [[[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil] fileSize];
        
        NSError *error;
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
        [[AVAudioSession sharedInstance] setActive:YES error:&error];
//        _buffer = [NAudioBuffer buffer];
//        [self createAudioFileStream];
    }return self;
}

/// 解析文件
- (void)createAudioFileStream
{
    NSLog(@"创建文件解析对象");
    self.audioFileStream = [[NAudioFileStream alloc] initWithFilePath:_filePath fileLength:_fileLength];
    _audioFileStream.delegate = self;
}

- (void)play
{
//    if (!self.audioQueue) {
//        NSLog(@"play, audioQueue is null");
//        return;
//    }
    
//    if ([_buffer bufferedSize] > 2048) {
//
////        NSLog(@"bufferedSize: %d", [_buffer bufferedSize]);
//    }
//
//    NSLog(@"bufferedSize: %d", [_buffer bufferedSize]);
//
//    BOOL isEof = NO;
//    UInt32 packetCount;
//    AudioStreamPacketDescription *desces = NULL;
//    NSData *data = [_buffer dequeueDataWithSize:2048 packetCount:&packetCount descriptions:&desces];
//
//    NSLog(@"data.length: %lu", (unsigned long)[data length]);
//    if (packetCount != 0){
//        [_audioQueue playData:data packetCount:packetCount packetDescriptions:desces isEof:isEof];
//        free(desces);
//    }
    
//    [self.audioQueue start];
    
    _thread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMain) object:nil];
    [_thread start];
}

- (void)pause
{
    if (self.audioQueue) {
        [self.audioQueue pause];
    }
}

- (void)stop
{
    if (self.audioQueue) {
        [self.audioQueue stop];
    }
}

- (void)playWithUrlString:(NSString *)urlString
{
    if (self.audioFileStream) {
        self.audioFileStream = nil;
        self.audioFileStream.delegate = nil;
    }
    
    if (self.audioQueue) {
        self.audioQueue = nil;
    }
    
    /// 创建文件解析对象
    [self createAudioFileStream];
}

- (void)threadMain
{
    /// 创建文件解析对象
    if (!self.audioFileStream) {
        [self createAudioFileStream];
    }
    
    /// 子线程开启定时器
    if (!_timer) {
        if (@available(iOS 10.0, *)) {
            _timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer * _Nonnull timer) {
                [self handleTask];
            }];
        } else {
            // Fallback on earlier versions
        }
        [[NSRunLoop currentRunLoop] run];
    }
}

/// 定时器
- (void)handleTask
{
//    NSLog(@"定时器 - -");
    
    NSData *data = [self.audioFileHandle readDataOfLength:2048];

    [_audioFileStream parseData:data]; /// 解析数据
}

#pragma mark NAudioFileStreamDelegate
/// 准备解析音频数据帧
- (void)audioStream_readyToProducePacketsWithAudioFileStream:(NAudioFileStream *)audioFileStream
{
    NSLog(@">>>>>>>>>>>> 准备解析音频数据帧 <<<<<<<<<<<<<<");
    
    /// 初始化audioQueue
    self.audioQueue = [[NAudioQueue alloc] initWithAudioDesc:audioFileStream.audioStreamBasicDescription];
}

///// 解析音频数据帧 ---- 开始播放
//- (void)audioStream_packetsWithAudioFileStream:(NAudioFileStream *)audioFileStream
//                                          audioDatas:(NSArray *)audioDatas
//{
//    NSLog(@">>>>>>>>>>>> 解析音频数据帧 ---- 开始播放 <<<<<<<<<<<<<<");
//
//    [_buffer enqueueFromDataArray:audioDatas];
//}

- (void)audioStream_packetsWithAudioFileStream:(NAudioFileStream *)audioFileStream data:(NSData *)data inNumberBytes:(UInt32)inNumberBytes inNumberPackets:(UInt32)inNumberPackets inPacketDescrrptions:(AudioStreamPacketDescription *)inPacketDescrrptions
{
    /// NSLog(@">>>>>>>>>>>> 解析音频数据帧(%ld)---- 开始播放 <<<<<<<<<<<<<<", [data length]);
    [_audioQueue playData:data inNumberPackets:inNumberPackets packetDescriptions:inPacketDescrrptions isEof:YES];
}

@end
