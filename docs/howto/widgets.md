# Add widgets and controls

## Add a widget

Long-press your iPhone's or iPad's Home Screen, tap Edit, then Add Widget, and search for the app. Choose Now, Recent, or Pinned and a size. For the Lock Screen, long-press it, tap Customize, and add the widget there. [Widgets and controls](../explanation/widgets.md) describes what each one shows.

A new widget reads "Open TimeTracking to finish setting up" until the first sync has delivered your data, so open the app once.

## Choose pinned projects

In the app, open Settings, Widgets, Pinned projects, and add and order your favorites. The list syncs across devices. "Task for pinned buttons" decides whether a button starts with the project's last task or with no task.

To give one widget its own list, long-press it and choose Edit Widget.

## Add a control

Open Control Center, long-press an empty spot, tap Add a Control, and search for the app. The Timer control toggles the timer. Start Project starts one project you choose, and it also suits the Action button: pick it in Settings, Action Button, Controls.

## Make widgets follow within seconds

Widgets on your iPhone and iPad update quickly only if your Mac can push to them. This takes an APNs key from your Apple Developer account, installed once.

1. In your Apple Developer account, under Certificates, IDs & Profiles, Keys, create a key with Apple Push Notifications service enabled, and download the `.p8` file.
2. On the Mac, after `make install`, store the key in the Keychain.

   ```sh
   make apns-key P8=~/Downloads/AuthKey_ABC123DEFG.p8
   ```

3. Check Settings, General, iCloud, on the Mac. The line "Widget updates" shows the state of the pushes.

The Mac app must be running for pushes to go out. Without it, widgets still update, only less promptly.
