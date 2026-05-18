import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  print('Starting logo padding script...');
  final file = File('assets/images/Logo.png');
  if (!file.existsSync()) {
    print('Error: assets/images/Logo.png not found!');
    return;
  }
  
  final bytes = file.readAsBytesSync();
  final image = img.decodePng(bytes);
  if (image == null) {
    print('Error: Failed to decode PNG image!');
    return;
  }
  
  final width = image.width;
  final height = image.height;
  print('Original image dimensions: ${width}x$height');
  
  // Create a new blank transparent image of the same size
  final padded = img.Image(width: width, height: height, numChannels: 4);
  padded.clear(img.ColorRgba8(0, 0, 0, 0));
  
  // Scale the original logo down to 60% to ensure it sits safely in the Android adaptive safe zone
  final targetWidth = (width * 0.60).toInt();
  final targetHeight = (height * 0.60).toInt();
  print('Resizing logo to: ${targetWidth}x$targetHeight (60%)');
  
  final resized = img.copyResize(
    image,
    width: targetWidth,
    height: targetHeight,
    interpolation: img.Interpolation.linear,
  );
  
  // Calculate centering coordinates
  final dstX = (width - targetWidth) ~/ 2;
  final dstY = (height - targetHeight) ~/ 2;
  print('Centering resized logo at: x=$dstX, y=$dstY');
  
  // Draw the resized logo onto the canvas
  img.compositeImage(
    padded,
    resized,
    dstX: dstX,
    dstY: dstY,
  );
  
  // Write the padded image back to file
  final pngBytes = img.encodePng(padded);
  File('assets/images/Logo_padded.png').writeAsBytesSync(pngBytes);
  print('Success! Padded logo generated at: assets/images/Logo_padded.png');
}
