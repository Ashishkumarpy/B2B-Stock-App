# Flutter Native & Engine standard rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.provider.** { *; }
-keep class *_GeneratedPluginRegistrant { *; }

# Firebase Messaging & Core rules
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Gson & JSON Serialization rules
-keepattributes InnerClasses,Signature,EnclosingMethod,*Annotation*,Synthetic
-dontwarn sun.misc.**
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Flutter Local Notifications rules (Fixes silent background/startup crashes)
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# Hive Database & Binary serialization rules
-keep class com.hivedb.** { *; }
-dontwarn com.hivedb.**
-keep class * extends io.hive.TypeAdapter { *; }

# Ignore missing Play Store core classes used by Flutter's deferred components
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
