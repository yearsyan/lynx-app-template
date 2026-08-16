# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Uncomment this to preserve the line number information for
# debugging stack traces.
#-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile

# The Lynx XElement umbrella AAR includes an optional Markdown adapter, while
# this template does not ship or register the Serval Markdown runtime. R8 still
# inspects those unreachable signatures, so suppress only their missing types.
-dontwarn com.lynx.markdown.IMarkdownEventListener
-dontwarn com.lynx.markdown.IResourceLoader
-dontwarn com.lynx.markdown.Markdown
-dontwarn com.lynx.markdown.MarkdownValuePack
-dontwarn com.lynx.markdown.ServalMarkdownView

# Lynx instantiates annotation-generated `$$PropsSetter` classes at runtime
# via string-based reflection; they have no direct code references, so R8
# strips them and every UI element fails to render (blank screen, errCode
# 9901 "Unable to instantiate methods getter").
-keep class **$$PropsSetter { *; }
-keep class **$$PropsSetter$* { *; }

# liblynxbase.so invokes LynxLog#log/logByte from native code via JNI by exact
# name and signature. Both are private static methods with no Java callers,
# so without this rule R8 removes/renames them and the release app aborts with
# "Failed to find static log(ILjava/lang/String;Ljava/lang/String;IJII)V".
-keepclassmembers class com.lynx.base.log.LynxLog {
    private static void log(int, java.lang.String, java.lang.String, int, long, int, int);
    private static void logByte(int, java.lang.String, byte[], int, long, int, int);
}
