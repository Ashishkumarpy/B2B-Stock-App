class ImageUrlUtils {
  /// Transforms a Cloudinary URL to request specific dimensions or quality.
  /// Example: https://res.cloudinary.com/demo/image/upload/sample.jpg
  /// Becomes: https://res.cloudinary.com/demo/image/upload/w_400,c_fill,q_auto/sample.jpg
  
  static String getThumbnail(String? url, {int width = 300, int height = 300}) {
    if (url == null || !url.contains('cloudinary.com')) return url ?? '';
    
    final parts = url.split('/upload/');
    if (parts.length != 2) return url;
    
    return '${parts[0]}/upload/w_$width,h_$height,c_fill,g_auto,q_auto,f_auto/${parts[1]}';
  }

  static String getHighRes(String? url) {
    if (url == null || !url.contains('cloudinary.com')) return url ?? '';
    
    final parts = url.split('/upload/');
    if (parts.length != 2) return url;
    
    return '${parts[0]}/upload/q_auto,f_auto/${parts[1]}';
  }

  static bool isLocalPath(String path) {
    return !path.startsWith('http');
  }
}
