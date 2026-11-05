# Screen capture on Linux

## X11

`desktopCapturer.getSources()` lists screens and windows with thumbnails,
and `getDisplayMedia({'video': {'deviceId': {'exact': id}}})` shares the one
picked, as on Windows.

## Wayland (the ScreenCast portal)

Under Wayland, applications can't list screens or windows: the
xdg-desktop-portal ScreenCast dialog is the picker, and the frames come
through PipeWire. libwebrtc reports this with
`RTCDesktopDevice::HasSystemPicker()`. A session counts as Wayland when
`XDG_SESSION_TYPE` is `wayland` and `WAYLAND_DISPLAY` is set, also for an
app forced onto XWayland (`GDK_BACKEND=x11`).

- **`getSources`** returns at once, with one placeholder source per type
  ("Screen", "Window"), no thumbnails, and no dialog. Apps should skip
  their own picker and call `getDisplayMedia` directly.
- **`getDisplayMedia`** opens one dialog that offers screens and windows.
  It completes only once the user has picked (a stream with one video
  track) or cancelled. The platform thread never waits for the portal:
  the portal's D-Bus traffic runs on the capturer's own thread and GLib
  main context.
- **Cancel:** dismissing the dialog fails the call with a message that
  starts with `NotAllowedError` (`Unable to getDisplayMedia:
  NotAllowedError: Permission denied: the screen share was cancelled`).
  A missing portal or a PipeWire failure gives `NotReadableError`.
  Nothing is left running, and the next call works.
- **Sharing the same source again:** the video track's
  `getSettings()['deviceId']` is a restore id. Passing it back as
  `video: {'deviceId': {'exact': id}}` shares the same screen or window
  without the dialog, while the app runs (the portal's transient restore
  token, `persist_mode` 1). Leave `deviceId` out, or pass `'0'`, to show
  the dialog.
- **Cursor:** the `cursor` constraint (`'always'`, the default, or
  `'never'`) asks the portal for an embedded cursor or none.
- **End:** when the share ends outside the app (the system's sharing
  indicator, the shared window closing, the portal session closing),
  `MediaStreamTrack.onEnded` fires. `track.stop()` closes the portal
  session.
- **A stream of the app's own portal session:**
  `video: {'pipewireStream': {'fd': fd, 'nodeId': nodeId, 'sessionHandle':
  handle}}` captures a PipeWire stream of a session the app opened itself,
  with no dialog: for example a RemoteDesktop session that also selected
  ScreenCast sources, so the user sees one dialog for control and sharing.
  The fd comes from the session's `OpenPipeWireRemote`; the plugin
  duplicates it and the caller keeps its own. With `sessionHandle`, the
  session's `Closed` signal ends the track.

Audio (`audio: true`) is the PulseAudio loopback, as on X11.
