# Project-specific R8/ProGuard keep rules for the release build.
#
# Flutter enables R8 code shrinking + obfuscation for release builds. Some
# libraries instantiate generated classes reflectively, so R8 must be told not
# to strip the members it can't see being called.
#
# KEEP THIS FILE MINIMAL. Every SDK we ship (Sentry, RevenueCat, Gson,
# androidx.work/room, install referrer) bundles its own consumer ProGuard
# rules inside its AAR — R8 merges those automatically. Wholesale
# `-keep class x.** { *; }` rules on top of them disable shrinking,
# obfuscation and optimisation for entire libraries; Play Console flagged
# exactly that (optimisation/obfuscation/shrinking rates below 30%). Only
# rules covering a failure the consumer rules demonstrably did NOT cover
# belong here.

# --- WorkManager + Room --------------------------------------------------
# androidx.work (pulled in transitively) auto-initialises WorkManager through
# androidx.startup at PROCESS START, before any Dart code runs. WorkManager
# builds its Room database by reflectively loading the Room-generated
# `WorkDatabase_Impl` (Room derives the impl name from the DB class's own name
# + "_Impl", so both the abstract DB and its generated impl must keep their
# original names and no-arg constructors). R8 full mode was renaming/stripping
# those, so Room threw
#   "Failed to create an instance of androidx.work.impl.WorkDatabase"
# and the app crashed on launch — a NATIVE crash no Dart try/catch can catch.
# This single rule matches transitive subclasses, so it covers both
# WorkDatabase and WorkDatabase_Impl without keeping the rest of
# androidx.work/room/sqlite (their own consumer rules handle the rest).
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-dontwarn androidx.work.**

# --- flutter_local_notifications -----------------------------------------
# (De)serialises its notification models with Gson via reflection: it needs
# its own model classes, Gson's TypeToken subclasses and the generic-signature
# metadata Gson reads at runtime. These are the rules the plugin documents;
# gson-core itself ships consumer rules, so no wholesale Gson keep.
-keep class com.dexterous.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepattributes Signature
-dontwarn com.dexterous.**

# --- Play Install Referrer -----------------------------------------------
# (play_install_referrer → com.android.installreferrer.) Backs the one-shot
# install attribution (InstallReferrerService): the referrer is only readable
# for 90 days per install, so if R8 breaks this channel the attribution burns
# its retry budget and is lost for good. The library is tiny — keep it
# wholesale; the cost is negligible.
-keep class com.android.installreferrer.** { *; }
-dontwarn com.android.installreferrer.**
