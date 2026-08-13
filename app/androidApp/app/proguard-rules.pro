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
