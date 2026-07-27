# Felicek release ProGuard/R8 rules.

# Flutter engine + embedding.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# The installer method channel is reached reflectively from Dart.
-keep class app.felicek.felicek.** { *; }

# WebRTC: the native layer calls back into these by name.
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# Firebase / Google Play services.
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Keep annotations used by the above.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
