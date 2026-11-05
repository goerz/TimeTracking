# Build and install the app

TimeTracking has no App Store or TestFlight release. You build it yourself, which takes about ten minutes the first time. By the end of this tutorial the app is in your Applications folder and the command-line tool answers in your terminal.

You need a Mac with macOS 27, Xcode 27 installed at `/Applications/Xcode.app`, and a paid Apple Developer Program membership, signed in to Xcode. The membership is what allows the app to use iCloud.

## Get the source

Open Terminal and clone the repository.

```sh
git clone https://github.com/goerz/TimeTracking.git
cd TimeTracking
```

## Enter your settings

Your personal build settings live in a file that git ignores. Create it from the template.

```sh
cp local.mk.example local.mk
```

Open `local.mk` in a text editor and fill in three values. `TEAM` is your ten-character development team ID, shown on the Membership page of your Apple Developer account. `BUNDLE_ID` is an identifier for the app that is unique to you, such as `com.yourname.timetracking`. `APP_NAME` is the name you want to see in Finder and the Dock; the default `TimeTracking` is fine.

## Build and install

```sh
make install
```

This builds the Mac app, checks the result, copies it to `/Applications`, and links two command-line tools into `~/.local/bin`. Xcode sets up signing and the app's iCloud containers on the way, so the first run takes longest.

Make sure `~/.local/bin` is on your `PATH`, then ask the tool for its version.

```sh
timetracking --version
```

It prints the tool's version and the version of the data format. Seeing that means the build worked.

## Open the app

Open the app from your Applications folder. A sheet asks "Set up activity tracking?". Click "Later" for now; the [next tutorial](first-day.md) doesn't need the tracker, and [Set up the activity tracker](../howto/tracker.md) covers it when you want it. Leave the checkbox on if you would like the app to open at login.

The main window opens on the Timer. Closing the window doesn't quit the app: a small dial stays in the menu bar at the top right of the screen.

## Add your iPhone or iPad

This part is optional. Connect the device and list its identifier.

```sh
make devices
```

Add a line such as `DEVICE_iphone = <UDID>` to `local.mk`, with the identifier from that list, then build and install.

```sh
make iphone
```

For an iPad, the line is `DEVICE_ipad` and the command is `make ipad`.

On first launch the app checks for an iCloud account. It must be the same account as on your Mac, with iCloud Drive turned on. The app then asks for a name for this device and shows "Receiving Your Data" while your entries arrive. After that you see the Timer, with the same entries as on the Mac.

Home Screen widgets follow changes within seconds only if the Mac can send them a push. [Add widgets and controls](../howto/widgets.md) explains the one extra step.

Continue with [Track your first day](first-day.md).
