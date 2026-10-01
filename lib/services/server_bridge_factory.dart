import 'dart:io';

import 'native_server_bridge.dart';
import 'desktop_server_bridge.dart';

/// Returns the [ServerBridge] implementation for the current platform.
///
/// Desktop (Windows/Linux/macOS) uses the pure-Dart [DesktopServerBridge] which
/// spawns the llama-server/cloudflared binaries directly. Android and iOS use
/// the native [NativeServerBridge] over the platform MethodChannel.
ServerBridge createServerBridge() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return DesktopServerBridge();
  }
  return const NativeServerBridge();
}
