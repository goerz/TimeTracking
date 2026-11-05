# Collect activity on iPhone and iPad

Collection is off by default and set up per device. What a device collects joins the [activity record](../explanation/tracked-and-recorded.md) through your Mac, so the Mac's tracker must be running to merge it. Any of the sources below works without the others.

Open Settings, Activity collection in the app, and turn on the master switch. The screen lists the steps, with a check mark once the app has received something from a step.

## Measure app use with Screen Time

Allow Screen Time access when asked. The group "Everything" then measures all use of the device, and you can add your own app groups, each with a name such as "Social" or "Reading" and the apps, categories, and sites you choose. Only the name reaches the record, never the apps.

## Record Safari sites

Turn on the app's extension under Settings, Apps, Safari, Extensions, and allow it on all websites. The extension sends the domain and path of the active tab, never query strings or page titles. [Exclusions](exclude.md) from the Mac's settings file apply here too, and the app's Privacy screen shows them.

## Mark Focus modes

In the system's Settings, Focus, add the app's Focus filter, "Log Activity", to a Focus and give it a name such as "Work". The record then shows when that Focus was on. "Record Safari Sites and Automations", on by default, can suspend those two sources while a Focus is on.

## Add automations

In the Shortcuts app, create a personal automation that runs the app's action "Log Activity Event", with a name and a type. Use this sparingly, for the two or three apps whose exact times matter, the charger, or arriving and leaving, because iOS posts a notification for every run.

## Check that it arrives

"Last sent" and "Waiting to send" show the state on the device, and "Send Now" sends right away. On the Mac, activity from the device carries a phone glyph in the Calendar.
