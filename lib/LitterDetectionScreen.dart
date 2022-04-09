import 'dart:developer';

import 'package:camera/camera.dart';
import 'package:clean_city_project/main.dart';
import 'package:clean_city_project/sample/object_detector_painter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

class LitterDetectorScreen extends StatefulWidget {
  const LitterDetectorScreen({Key? key}) : super(key: key);

  @override
  _LitterDetectorScreenState createState() => _LitterDetectorScreenState();
}

class _LitterDetectorScreenState extends State<LitterDetectorScreen>
    with WidgetsBindingObserver {
  CameraController? controller;
  late CameraDescription camera;

  //todo how do you load it from firebase? RemoteModel
  LocalModel model = LocalModel("model.tflite");
  late ObjectDetector objectDetector;
  CustomPaint? customPaint;

  @override
  void initState() {
    super.initState();
    objectDetector = GoogleMlKit.vision.objectDetector(
        CustomObjectDetectorOptions(model,
            trackMutipleObjects: true, classifyObjects: true));
    camera = cameras.first;
    onNewCameraSelected(camera);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = controller;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      onNewCameraSelected(cameraController.description);
    }
    super.didChangeAppLifecycleState(state);
  }

  Future<void> onNewCameraSelected(CameraDescription cameraDescription) async {
    if (controller != null) {
      await controller!.dispose();
    }

    final CameraController cameraController = CameraController(
      cameraDescription,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    controller = cameraController;

    // If the controller is updated then update the UI.
    cameraController.addListener(() {
      if (mounted) {
        setState(() {});
      }
      if (cameraController.value.hasError) {
        log('Camera error ${cameraController.value.errorDescription}');
      }
    });

    try {
      await cameraController.initialize();
    } on CameraException catch (e) {
      log(e.description.toString());
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    objectDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return const Text(
        'Tap a camera',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(),
      body: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(controller!),
              if (customPaint != null) Expanded(child: customPaint!)
            ],
          )),
      bottomNavigationBar: buildBottomBar(),
    );
  }

  Row buildBottomBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          child: const Text("Start"),
          onPressed: startDetection,
        )
      ],
    );
  }

  void startDetection() {
    controller!.startImageStream((image) => {newCameraImage(image)});
  }

  bool isBusy = false;

  void newCameraImage(CameraImage cameraImage) async {
    if (isBusy) return;
    isBusy = true;

    final WriteBuffer allBytes = WriteBuffer();
    for (Plane plane in cameraImage.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize =
        Size(cameraImage.width.toDouble(), cameraImage.height.toDouble());

    final InputImageRotation imageRotation =
        InputImageRotationMethods.fromRawValue(camera.sensorOrientation) ??
            InputImageRotation.Rotation_0deg;

    final InputImageFormat inputImageFormat =
        InputImageFormatMethods.fromRawValue(cameraImage.format.raw) ??
            InputImageFormat.NV21;

    final planeData = cameraImage.planes.map(
      (Plane plane) {
        return InputImagePlaneMetadata(
          bytesPerRow: plane.bytesPerRow,
          height: plane.height,
          width: plane.width,
        );
      },
    ).toList();

    final inputImageData = InputImageData(
      size: imageSize,
      imageRotation: imageRotation,
      inputImageFormat: inputImageFormat,
      planeData: planeData,
    );

    final inputImage =
        InputImage.fromBytes(bytes: bytes, inputImageData: inputImageData);

    // analyze image
    // TODO use CustomObjectDetectorOptions
    final List<DetectedObject> _objects =
        await objectDetector.processImage(inputImage);

    if (inputImage.inputImageData?.size != null &&
        inputImage.inputImageData?.imageRotation != null &&
        _objects.isNotEmpty) {
      log("_objects size is ${_objects.length}");
      final painter = ObjectDetectorPainter(
          _objects,
          inputImage.inputImageData!.imageRotation,
          inputImage.inputImageData!.size);
      customPaint = CustomPaint(painter: painter);
    } else {
      customPaint = null;
    }

    isBusy = false;
    if (mounted) {
      setState(() {});
    }

    // outputs
    // for (DetectedObject detectedObject in _objects) {
    //   final rect = detectedObject.getBoundinBox();
    //   final trackingId = detectedObject.getTrackingId();
    //
    //   for (Label label in detectedObject.getLabels()) {
    //     log('object : ${label.getText()} ${label.getConfidence()}');
    //   }
    // }
  }
}
