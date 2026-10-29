# Flutter embedding and plugins are accessed reflectively by the engine.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep annotations used by reflection-based serialization.
-keepattributes *Annotation*

# Play Core is optional in the Flutter engine (deferred components).
-dontwarn com.google.android.play.core.**
