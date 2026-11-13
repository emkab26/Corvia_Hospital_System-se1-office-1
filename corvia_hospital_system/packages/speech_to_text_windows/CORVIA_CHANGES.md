Based on speech_to_text_windows 1.0.1 (license retained).

Corvia adds inputDevices and selectInputDevice methods to the existing Windows
channel. Selection targets only this recognizer through ISpMMSysAudio; it does
not modify the Windows default input. Empty ID uses WAVE_MAPPER. Device IDs are
session-only and validated against a fresh device enumeration before applying.
