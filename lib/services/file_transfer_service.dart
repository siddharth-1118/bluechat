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
}
