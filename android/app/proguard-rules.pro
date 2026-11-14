# irondash methods are reached only from Rust over JNI, so R8 sees them as unused.
-keep class dev.irondash.** { *; }
