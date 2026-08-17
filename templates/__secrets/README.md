# `__secrets/`

Everything in this folder is gitignored except this README. Drop the files
listed below in here and the local release build plus the store upload lanes
pick them up automatically.

Nothing here is read at runtime by the app. These are build-time and
publish-time credentials only. Client-visible configuration (ad unit IDs,
RevenueCat public keys, the Sentry DSN) belongs in `.env` instead.

Android needs the first three. iOS needs the last two. Nothing stops you from
setting up one platform and ignoring the other.

## Android

### 1. The upload keystore

Create it once:

```bash
keytool -genkey -v -keystore __secrets/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Back it up somewhere that is not this laptop. Losing it means you can never
update the app under that Play listing again without a Play support reset.

### 2. The signing credentials

Two file layouts are accepted, and the build tries them in this order:

1. **`keystore.env`** with `ANDROID_*` names. This is the shared studio format,
   so a common credentials file can be dropped in untouched, without renaming
   keys that other projects also read.
2. **`keystore.properties`** with the Gradle-conventional names.

Either way the values are the same three things: where the keystore is, how to
open it, and which key inside it to use.

```
# __secrets/keystore.env
ANDROID_KEYSTORE_PATH=__secrets/upload-keystore.jks
ANDROID_KEYSTORE_PASSWORD=
ANDROID_KEY_ALIAS=upload
# Leave blank to reuse the keystore password, which is what keytool does when
# you press enter at its prompt.
ANDROID_KEY_PASSWORD=
```

### 3. The Play service account

`play-service-account.json`, from Play Console > Setup > API access. Grant it
the "Release manager" role. Used by fastlane supply on
`make android:aab:submit`.

## iOS

### 4. The App Store Connect API key

`AuthKey_XXXXXXXX.p8`, from App Store Connect > Users and Access > Integrations
> App Store Connect API. Note the key ID and issuer ID printed alongside it;
they go in `keystore.env` too:

```
APP_STORE_CONNECT_KEY_ID=
APP_STORE_CONNECT_ISSUER_ID=
```

### 5. The distribution certificate and provisioning profile

Managed by Xcode automatic signing in most cases. If you are using manual
signing or fastlane match, the exported `.p12` and `.mobileprovision` go here.

## What must never go in here

- The RevenueCat **secret** API key. It is server-side only and the app never
  needs it.
- Anything the app reads at runtime. That belongs in `.env`.
