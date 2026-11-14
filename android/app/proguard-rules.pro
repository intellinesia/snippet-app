# Rust reaches these over JNI by name and signature, so R8 must neither strip nor rename them.
-keep class dev.irondash.** { *; }
-keep class io.flutter.view.TextureRegistry { *; }
-keep class io.flutter.view.TextureRegistry$** { *; }
-keep class io.flutter.plugin.common.BinaryMessenger { *; }
-keep class io.flutter.embedding.engine.FlutterJNI { *; }
