# Project-specific R8/ProGuard keep rules for the release build.
#
# Flutter enables R8 code shrinking + obfuscation for release builds. Some
# libraries instantiate generated classes reflectively, so R8 must be told not
# to strip the members it can't see being called.

# --- WorkManager + Room --------------------------------------------------
# androidx.work:work-runtime (pulled in transitively — play-services-ads →
# androidx.work) auto-initialises WorkManager through androidx.startup at
# PROCESS START, before any Dart code runs. WorkManager builds its Room
# database by reflectively loading the Room-generated `WorkDatabase_Impl`
# (Room computes the impl name from the DB class's own name + "_Impl", so BOTH
# the abstract DB and its generated impl must keep their original names). R8
# was renaming/stripping those, so Room threw
#   "Failed to create an instance of androidx.work.impl.WorkDatabase"
# and the app crashed on launch — a NATIVE crash no Dart try/catch can catch,
# which is why release/Play-Store builds "open then immediately close".
#
# These keeps previously lived here for the now-removed home_widget plugin and
# were deleted with it; WorkManager is still present transitively, so they are
# required. See android/app/build.gradle.kts (R8 is on for release).
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-keep class androidx.sqlite.** { *; }
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-dontwarn androidx.work.**

# --- Startup SDKs (native platform-channel plugins) ----------------------
# Insurance against the same failure mode as above. Every SDK in main()'s boot
# sequence talks to native code over a Flutter method channel. If R8 strips or
# renames a plugin's native handler, the Dart-side `await` on that channel never
# gets its reply and the app hangs on the splash forever — a release-only stall
# no Dart try/catch can see. `_startApp` now bounds each init with a timeout so
# a break degrades gracefully, but keeping these classes means the feature keeps
# WORKING rather than merely failing quietly. Most ship consumer rules already;
# these are explicit belt-and-braces for the ones that boot before any UI.

# Sentry (installed first — wraps the whole app, incl. the native crash handler)
-keep class io.sentry.** { *; }
-dontwarn io.sentry.**

# Google Mobile Ads + UMP consent — the heaviest native stack (pulls
# play-services, and WorkManager transitively; see the Room keeps above).
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.android.ump.** { *; }
-dontwarn com.google.android.gms.**

# RevenueCat (purchases_flutter / purchases_ui_flutter). The native SDK aborts
# the process on bad state, so a mangled class is especially unforgiving.
-keep class com.revenuecat.** { *; }
-dontwarn com.revenuecat.**

# flutter_local_notifications (de)serialises its notification models with Gson
# via reflection — it needs both its own classes and Gson's generic machinery.
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-dontwarn com.dexterous.**

# Play Install Referrer (play_install_referrer → com.android.installreferrer).
# Backs the one-shot install attribution (InstallReferrerService): the referrer
# is only readable for 90 days per install, so if R8 breaks this channel the
# attribution burns its retry budget and is lost for good. The library is tiny —
# keep it wholesale.
-keep class com.android.installreferrer.** { *; }
-dontwarn com.android.installreferrer.**
