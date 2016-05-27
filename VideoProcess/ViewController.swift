//
//  ViewController.swift
//  VideoProcess
//
//  Created by zq liu on 16/5/25.
//  Copyright © 2016年 zq liu. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController,AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureMetadataOutputObjectsDelegate {
    let captureSession=AVCaptureSession()
    //视频预览层
    var previewLayer:CALayer!
    lazy var context:CIContext={
        //使用OpenGL，保证了更快的渲染速度和更好的性能
        let eaglCon=EAGLContext(API: EAGLRenderingAPI.OpenGLES2)
        //关闭颜色管理功能
        let opt=[kCIContextWorkingColorSpace:NSNull()]
        return CIContext(EAGLContext:eaglCon,options: opt)
    }()
    var faceLayer: CALayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        //添加视频预览层
        previewLayer = CALayer()
        //把bounds的顶点从中心变为左上角
        previewLayer.anchorPoint = CGPointZero
        previewLayer.bounds = view.bounds
        previewLayer.contentsGravity = kCAGravityResizeAspect
        self.view.layer.insertSublayer(previewLayer, atIndex: 0)
        
        //加载摄像头
        captureSession.sessionPreset = AVCaptureSessionPresetPhoto
        let devices = AVCaptureDevice.devices()
        for device in devices {
            if (device.hasMediaType(AVMediaTypeVideo)) {
                //前置摄像头
                if (device.position == AVCaptureDevicePosition.Front) {
                    if let captureDevice=try? AVCaptureDeviceInput(device: device as! AVCaptureDevice) {
                        if captureSession.canAddInput(captureDevice) {
                            captureSession.addInput(captureDevice)
                            setupSessionOutput()
                            captureSession.startRunning()
                        }
                    }
                }
            }
        }
    }

    func setupSessionOutput() {
        //添加输出设备到session中，这里添加的是AVCaptureVideoDataOutput，表示视频里的每一帧，除此之外，还有AVCaptureMovieFileOutput（完整的视频）、AVCaptureAudioDataOutput（音频）、AVCaptureStillImageOutput（静态图）等
        let output = AVCaptureVideoDataOutput()
        let cameraQueue = dispatch_queue_create("cameraQueue", DISPATCH_QUEUE_SERIAL)
        output.setSampleBufferDelegate(self, queue: cameraQueue)
        //videoSettings指定一个字典，但是目前只支持kCVPixelBufferPixelFormatTypeKey，用它指定像素的输出格式，这个参数直接影响到生成图像的成功与否
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA)]
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
        }
        
        //添加人脸检测，AVFoundation框架内置了检测人脸的功能
        let metadataOutput = AVCaptureMetadataOutput()
        metadataOutput.setMetadataObjectsDelegate(self, queue: dispatch_get_main_queue())
        
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.metadataObjectTypes = [AVMetadataObjectTypeFace]
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    //适应屏幕旋转
    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator
        coordinator: UIViewControllerTransitionCoordinator) {
        previewLayer.bounds.size = size
    }
    
    func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        //处理过程中用到了很多对象，比较占用内存，因此手动增加了自动释放池
        autoreleasepool {
            let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
            var outputImage = CIImage(CVPixelBuffer: imageBuffer)
            
            //图像方向调整
            let orientation = UIDevice.currentDevice().orientation
            var t: CGAffineTransform!
            if orientation == UIDeviceOrientation.Portrait {
                t = CGAffineTransformMakeRotation(CGFloat(-M_PI / 2.0))
            } else if orientation == UIDeviceOrientation.PortraitUpsideDown {
                t = CGAffineTransformMakeRotation(CGFloat(M_PI / 2.0))
            } else if (orientation == UIDeviceOrientation.LandscapeLeft) {
                //前置摄像头(LandscapeLeft),后置摄像头(LandscapeRight)
                t = CGAffineTransformMakeRotation(CGFloat(M_PI))
            }
            else {
                t = CGAffineTransformMakeRotation(0)
            }
            outputImage = outputImage.imageByApplyingTransform(t)
            
            let cgImage = context.createCGImage(outputImage, fromRect: outputImage.extent)
            //输出预览内容
            dispatch_sync(dispatch_get_main_queue(), {
                self.previewLayer.contents = cgImage
            })
        }
    }
    
    //人脸识别(界面标记)
    func captureOutput(captureOutput: AVCaptureOutput!, didOutputMetadataObjects metadataObjects: [AnyObject]!, fromConnection connection: AVCaptureConnection!) {
        
        if metadataObjects.count > 0 {
            
            //人脸识别(界面标记)
            //识别到的第一张脸
            let faceObject = metadataObjects.first as! AVMetadataFaceObject
            
            if faceLayer == nil {
                faceLayer = CALayer()
                faceLayer?.borderColor = UIColor.redColor().CGColor
                faceLayer?.borderWidth = 1
                view.layer.addSublayer(faceLayer!)
            }
            let faceBounds = faceObject.bounds
            let viewSize = view.bounds.size
            //从AVFoundation视频中取到的bounds，是一个0～1之间的数，是相对于图像的百分比，所以在设置position时，做两步：把x、y颠倒，修正方向等问题，这里只是简单地适配了Portrait方向，达到目的即可；再和view的宽、高相乘，其实是和Layer的父Layer的宽、高相乘
            //提示：bounds的坐标原点在原始图像左上角，旋转后界面坐标原点在屏幕左上角
            //-90算法
//            faceLayer?.position = CGPoint(x: viewSize.width * (1 - faceBounds.origin.y - faceBounds.size.height / 2), y: viewSize.height * (faceBounds.origin.x + faceBounds.size.width / 2))
            //90算法
//            faceLayer?.position = CGPoint(x: viewSize.width * (faceBounds.origin.y + faceBounds.size.height / 2), y: viewSize.height * (1 - faceBounds.origin.x - faceBounds.size.width / 2))
            //size算法
//            faceLayer?.bounds.size = CGSize(width: faceBounds.size.height * viewSize.width, height: faceBounds.size.width * viewSize.height)
            
            //0算法
//            faceLayer?.position = CGPoint(x: viewSize.width * (faceBounds.origin.x + faceBounds.size.width / 2), y: viewSize.height * (faceBounds.origin.y + faceBounds.size.height / 2))
            //180算法
            faceLayer?.position = CGPoint(x: viewSize.width * (1-faceBounds.origin.x - faceBounds.size.width / 2), y: viewSize.height * (1-faceBounds.origin.y - faceBounds.size.height / 2))
            //size算法
            faceLayer?.bounds.size = CGSize(width: faceBounds.size.width * viewSize.width, height: faceBounds.size.height * viewSize.height)
  
        }
    }
}

