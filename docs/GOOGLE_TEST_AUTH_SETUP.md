# Google test authentication setup

This private build uses Supabase Google OAuth. Keep it on test accounts until production approval.

## Google Auth Platform

- Android package: `com.example.folk_guide_app`
- Debug SHA-1: `9D:03:FF:41:34:7E:66:82:38:4F:62:C4:16:71:CF:AB:34:FA:D7:AF`
- Debug SHA-256: `E0:C3:59:B4:2F:FF:79:80:7C:13:91:A9:46:53:39:9B:AE:5F:2D:A6:19:F9:24:9D:97:F4:90:4A:3F:36:F5:D8`

Create an Android OAuth client with the package and SHA-1 above. The Google provider in Supabase also needs a Web OAuth client ID and secret.

## Supabase Auth

- OAuth callback: `https://eztlkvzgiepgpylayapv.supabase.co/auth/v1/callback`
- Allowed mobile redirect: `com.example.folk_guide_app://login-callback/`

Add the Android and Web client IDs to the Google provider's authorized client IDs. Add the mobile redirect to the Supabase redirect allow list.

Do not commit the Google client secret or a Supabase service-role key. The Supabase publishable key is supplied at build time through `--dart-define`.
