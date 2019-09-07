/// Copyright (c) 2019 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import AVFoundation
import UIKit
import Vision

class FaceDetectionViewController: UIViewController {
  var sequenceHandler = VNSequenceRequestHandler() // defines the request handler that'll be feeding images to from the camera feed.

  @IBOutlet var faceView: FaceView!
  @IBOutlet var laserView: LaserView!
  @IBOutlet var faceLaserLabel: UILabel!
  
  var session = AVCaptureSession()
  var previewLayer: AVCaptureVideoPreviewLayer!
  
  var dataOutputQueue = DispatchQueue(
    label: "video data queue",
    qos: .userInitiated,
    attributes: [],
    autoreleaseFrequency: .workItem)

  var faceViewHidden = false
  
  var maxX: CGFloat = 0.0
  var midY: CGFloat = 0.0
  var maxY: CGFloat = 0.0

  var useFrontCamera = false
  
  override func viewDidLoad() {
    super.viewDidLoad()
    configureCaptureSession()
    
    laserView.isHidden = true
    
    maxX = view.bounds.maxX
    midY = view.bounds.midY
    maxY = view.bounds.maxY
    
    session.startRunning()
  }
  
  @IBAction func switchCamera( sender: UISwitch){
    if sender.isOn {
      print("UISwitch is ON")
      useFrontCamera = true
    }
    else {
      print("UISwitch is OFF")
      useFrontCamera = false
    }
    guard let currentCameraInput: AVCaptureInput = session.inputs.first else {
      return
    }
    guard let currentCameraOutput: AVCaptureOutput = session.outputs.first else {
      return
    }
    session.removeInput(currentCameraInput)
    session.removeOutput(currentCameraOutput)
    configureCaptureSession()
    
    laserView.isHidden = true
    
    maxX = view.bounds.maxX
    midY = view.bounds.midY
    maxY = view.bounds.maxY
    session.startRunning()
  }
  
}

// MARK: - Gesture methods

extension FaceDetectionViewController {
  @IBAction func handleTap(_ sender: UITapGestureRecognizer) {
    faceView.isHidden.toggle()
    laserView.isHidden.toggle()
    faceViewHidden = faceView.isHidden
    
    if faceViewHidden {
      faceLaserLabel.text = "None"
    } else {
      faceLaserLabel.text = "Marked"
    }
  }
}

// MARK: - Video Processing methods

extension FaceDetectionViewController {
  func configureCaptureSession() {
    // Define the capture device we want to use
    var cameraPosition: AVCaptureDevice.Position!
    if useFrontCamera {
      cameraPosition = AVCaptureDevice.Position.front
    }
    else{
      cameraPosition = AVCaptureDevice.Position.back
    }
    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                               for: .video,
                                               position: cameraPosition) else {
      fatalError("No video camera available")
    }
    
    // Connect the camera to the capture session input
    do {
      let cameraInput = try AVCaptureDeviceInput(device: camera)
      session.addInput(cameraInput)
    } catch {
      fatalError(error.localizedDescription)
    }
    
    // Create the video data output
    let videoOutput = AVCaptureVideoDataOutput()
    videoOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
    videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    
    // Add the video output to the capture session
    session.addOutput(videoOutput)
    
    let videoConnection = videoOutput.connection(with: .video)
    videoConnection?.videoOrientation = .portrait
    
    // Configure the preview layer
    previewLayer = AVCaptureVideoPreviewLayer(session: session)
    previewLayer.videoGravity = .resizeAspectFill
    previewLayer.frame = view.bounds
    view.layer.insertSublayer(previewLayer, at: 0)
  }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate methods

extension FaceDetectionViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    // 1. Get the image buffer from the passed in sample buffer.
    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return
    }

    // 2. Create a face detection request to detect face bounding boxes and pass the results to a completion handler.
    let detectFaceRequest = VNDetectFaceLandmarksRequest(completionHandler: detectedFace)

    // 3. Use sequence request handler to perform face detection request on the image.
    do {
      try sequenceHandler.perform(
        [detectFaceRequest],
        on: imageBuffer,
        orientation: .leftMirrored)
    } catch {
      print(error.localizedDescription)
    }
  }
}

extension FaceDetectionViewController {
  func convert(rect: CGRect) -> CGRect {
    
    if useFrontCamera{
      //print("input \(rect)")
      // 1
      let origin = previewLayer.layerPointConverted(fromCaptureDevicePoint: rect.origin)
      //print("origin \(origin)")
      
      // 2
      let size = previewLayer.layerPointConverted(fromCaptureDevicePoint: rect.size.cgPoint)
      //print("size \(size)")
      // 3
      return CGRect(origin: origin, size: size.cgSize)
    }
    else{
      // 1
      let opposite = rect.origin + rect.size.cgPoint
      let origin = previewLayer.layerPointConverted(fromCaptureDevicePoint: rect.origin)
      
      // 2
      let opp = previewLayer.layerPointConverted(fromCaptureDevicePoint: opposite)
      
      // 3
      let size = (opp - origin).cgSize
      return CGRect(origin: origin, size: size)
    }
  }

  // 1
  func landmark(point: CGPoint, to rect: CGRect) -> CGPoint {
    // 2
    let absolute = point.absolutePoint(in: rect)

    // 3
    let converted = previewLayer.layerPointConverted(fromCaptureDevicePoint: absolute)

    // 4
    return converted
  }

  func landmark(points: [CGPoint]?, to rect: CGRect) -> [CGPoint]? {
    guard let points = points else {
      return nil
    }

    return points.compactMap { landmark(point: $0, to: rect) }
  }
  
  func updateFaceView(for results: [VNFaceObservation]) {
    defer {
      DispatchQueue.main.async {
        self.faceView.setNeedsDisplay()
      }
    }
    for result in results{
      print("draw")
      let box = result.boundingBox
      faceView.boundingBox = convert(rect: box)
      
      guard let landmarks = result.landmarks else {
        return
      }
      
      if let leftEye = landmark(
        points: landmarks.leftEye?.normalizedPoints,
        to: result.boundingBox) {
        faceView.leftEye = leftEye
      }
      
      if let rightEye = landmark(
        points: landmarks.rightEye?.normalizedPoints,
        to: result.boundingBox) {
        faceView.rightEye = rightEye
      }
      
      if let leftEyebrow = landmark(
        points: landmarks.leftEyebrow?.normalizedPoints,
        to: result.boundingBox) {
        faceView.leftEyebrow = leftEyebrow
      }
      
      if let rightEyebrow = landmark(
        points: landmarks.rightEyebrow?.normalizedPoints,
        to: result.boundingBox) {
        faceView.rightEyebrow = rightEyebrow
      }
      
      if let nose = landmark(
        points: landmarks.nose?.normalizedPoints,
        to: result.boundingBox) {
        faceView.nose = nose
      }
      
      if let outerLips = landmark(
        points: landmarks.outerLips?.normalizedPoints,
        to: result.boundingBox) {
        faceView.outerLips = outerLips
      }
      
      if let innerLips = landmark(
        points: landmarks.innerLips?.normalizedPoints,
        to: result.boundingBox) {
        faceView.innerLips = innerLips
      }
      
      if let faceContour = landmark(
        points: landmarks.faceContour?.normalizedPoints,
        to: result.boundingBox) {
        faceView.faceContour = faceContour
      }
    }
    
  }

  // 1
  func updateLaserView(for result: VNFaceObservation) {
    // 2
    laserView.clear()

    // 3
    let yaw = result.yaw ?? 0.0

    // 4
    if yaw == 0.0 {
      return
    }

    // 5
    var origins: [CGPoint] = []

    // 6
    if let point = result.landmarks?.leftPupil?.normalizedPoints.first {
      let origin = landmark(point: point, to: result.boundingBox)
      origins.append(origin)
    }

    // 7
    if let point = result.landmarks?.rightPupil?.normalizedPoints.first {
      let origin = landmark(point: point, to: result.boundingBox)
      origins.append(origin)
    }

    // 1
    let avgY = origins.map { $0.y }.reduce(0.0, +) / CGFloat(origins.count)

    // 2
    let focusY = (avgY < midY) ? 0.75 * maxY : 0.25 * maxY

    // 3
    let focusX = (yaw.doubleValue < 0.0) ? -100.0 : maxX + 100.0

    // 4
    let focus = CGPoint(x: focusX, y: focusY)

    // 5
    for origin in origins {
      let laser = Laser(origin: origin, focus: focus)
      laserView.add(laser: laser)
    }

    // 6
    DispatchQueue.main.async {
      self.laserView.setNeedsDisplay()
    }
  }

  func detectedFace(request: VNRequest, error: Error?) {
    // 1. Extract the first result from the array of face observation results.
    guard
      let results = request.results as? [VNFaceObservation]
      else {
        // 2. Clear the FaceView if something goes wrong or no face is detected.
        faceView.clear()
        return
    }
    if results.count != 0 {
      print(results.count)
    }
    // 3. Set the bounding box to draw in the FaceView after converting it from the coordinates in the VNFaceObservation.
    if faceViewHidden {
      //updateLaserView(for: results)
    }
    else {
      updateFaceView(for: results)
    }
  }
}
