// A file picked on disk, read in ranges. Desktop only; the browser build has no files to read this way.
export 'file_source_stub.dart' if (dart.library.io) 'file_source_io.dart';
