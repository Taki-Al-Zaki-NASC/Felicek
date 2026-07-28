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

# Play Core (deferred components / split installs).
#
# Flutter's embedding always references these classes —
# FlutterPlayStoreSplitApplication and PlayStoreDeferredComponentManager —
# whether or not an app uses deferred components. Felicek does not, and it is
# distributed as a single standalone APK from a website rather than through the
# Play Store, so the Play Core library is deliberately not a dependency.
#
# That combination makes R8 fail the release build on missing classes. The code
# paths that reference them are unreachable here (nothing constructs the
# Play Store application or component manager), so suppressing the warning is
# correct rather than papering over a real absence.
#
# If this app ever ships deferred components, add the real Play Core dependency
# instead of widening this rule.
-dontwarn com.google.android.play.core.**

# Keep annotations used by the above.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
