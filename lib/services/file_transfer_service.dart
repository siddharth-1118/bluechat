import 'package:file_picker/file_picker.dart';

class FileTransferService {
  static Future<FilePickerResult?> pickFile(String type) async {
    FileType fileType = FileType.any;
    List<String>? allowedExtensions;

    switch (type) {
      case 'image':
        fileType = FileType.image;
        break;
      case 'video':
        fileType = FileType.video;
        break;
      case 'audio':
        fileType = FileType.audio;
        break;
      case 'pdf':
        fileType = FileType.custom;
        allowedExtensions = ['pdf'];
        break;
      case 'doc':
        fileType = FileType.custom;
        allowedExtensions = ['doc', 'docx', 'txt', 'xls', 'xlsx', 'ppt', 'pptx', 'rtf'];
        break;
      case 'apk':
        fileType = FileType.custom;
        allowedExtensions = ['apk'];
        break;
      default:
        fileType = FileType.any;
    }

    try {
      return await FilePicker.platform.pickFiles(
        type: fileType,
        allowedExtensions: allowedExtensions,
        allowCompression: false,
      );
    } catch (e) {
      // File picking error or permission denied
      return null;
    }
  }

  static String getReadableFileSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB"];
    double size = bytes.toDouble();
    int suffixIndex = 0;
    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }
    return "${size.toStringAsFixed(1)} ${suffixes[suffixIndex]}";
  }

  static String getReadableSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return "0 B/s";
    const suffixes = ["B/s", "KB/s", "MB/s", "GB/s"];
    double speed = bytesPerSec;
    int suffixIndex = 0;
    while (speed >= 1024 && suffixIndex < suffixes.length - 1) {
      speed /= 1024;
      suffixIndex++;
    }
    return "${speed.toStringAsFixed(1)} ${suffixes[suffixIndex]}";
  }

  /// Returns a MIME type for a file name, used when sharing files to other apps.
  static String getMimeType(String? fileName) {
    if (fileName == null || !fileName.contains('.')) return "*/*";
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return "image/jpeg";
      case 'png':
        return "image/png";
      case 'gif':
        return "image/gif";
      case 'webp':
        return "image/webp";
      case 'bmp':
        return "image/bmp";
      case 'mp4':
        return "video/mp4";
      case 'mov':
        return "video/quicktime";
      case '3gp':
        return "video/3gpp";
      case 'mkv':
        return "video/x-matroska";
      case 'webm':
        return "video/webm";
      case 'avi':
        return "video/x-msvideo";
      case 'mp3':
        return "audio/mpeg";
      case 'wav':
        return "audio/wav";
      case 'aac':
        return "audio/aac";
      case 'flac':
        return "audio/flac";
      case 'ogg':
        return "audio/ogg";
      case 'pdf':
        return "application/pdf";
      case 'apk':
        return "application/vnd.android.package-archive";
      case 'txt':
        return "text/plain";
      case 'doc':
        return "application/msword";
      case 'docx':
        return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
      case 'xls':
        return "application/vnd.ms-excel";
      case 'xlsx':
        return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
      case 'ppt':
        return "application/vnd.ms-powerpoint";
      case 'pptx':
        return "application/vnd.openxmlformats-officedocument.presentationml.presentation";
      case 'rtf':
        return "application/rtf";
      case 'zip':
        return "application/zip";
      default:
        return "*/*";
    }
  }
}
