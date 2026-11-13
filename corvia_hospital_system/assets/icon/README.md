# Corvia App Icon

Drop two PNGs in this folder before running the icon generator:

| File                              | Size           | Purpose                                                |
| --------------------------------- | -------------- | ------------------------------------------------------ |
| `corvia_icon.png`                 | 1024 × 1024 px | Master icon (used for iOS, web, Windows, Android)      |
| `corvia_icon_foreground.png`      | 1024 × 1024 px | Foreground layer for Android adaptive icons (transparent background, important content centred in the inner ~66% safe area) |

After dropping the files in:

```bash
flutter pub get
dart run flutter_launcher_icons
```

This will regenerate `mipmap-*/ic_launcher.png`, the iOS `AppIcon.appiconset`,
the web `icons/`, and Windows `app_icon.ico`. No manual edits required.

## Quick placeholder

Until a designed logo is ready, any 1024×1024 dark-blue PNG with the letter "C"
in white (Helvetica Bold) is a good starting point. Background hex
`#0D1B2A`, foreground hex `#00B4D8`.
