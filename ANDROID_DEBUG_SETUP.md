# Android debug setup

`bootstrap_*` first generates the Android host with the Flutter SDK installed on the developer PC, then patches:

- INTERNET
- FINE/COARSE location
- FOREGROUND_SERVICE
- FOREGROUND_SERVICE_LOCATION
- cleartext HTTP for the local debug server

This is deliberately for local/debug testing. Production should use HTTPS and a production network-security policy.
