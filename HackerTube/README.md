# HackerTube Home

A companion library for the sideloaded YouTube app. With its switch on, the Home tab shows
[hackertube.org](https://hackertube.org/) in a web view in place of YouTube's feed, and a video
tapped there plays in YouTube's own player. The top bar, the other tabs, search and playback are
untouched. The library depends on nothing else in this repository.

## Switch

YouTube Settings has a HackerTube section with one switch, "HackerTube Home", off by default. The
switch is saved in the app's standard user defaults under `HackerTubeHomeEnabled` and read once at
launch, so a change applies after YouTube restarts. While it is off the library hooks only the
Settings list.

## Dependencies

- **hackertube.org is reachable.** The library keeps no offline copy of the page. When the page
  cannot load, Home shows a message with a Retry button.
- **The site's cards stay links to a video.** A link to `/watch/<video id>` on the site, or to
  `youtube.com/watch?v=<video id>`, opens the native player; the id must be 11 characters of
  `A-Z a-z 0-9 _ -`. Other links on the site stay in the web view, tapped links to other sites
  open outside the app, and nothing else can take the web view off the site.
- **The site follows same-site links from a click listener on the document.** The library
  registers its own listener first and keeps watch links away from the site's, so the tap becomes
  a navigation that the library hands to the player. If the site starts handling card taps in a
  listener that runs before the library's, such as one on the card itself, a tap shows the site's
  own watch page with its embedded player.
- **YouTube keeps the members listed in `HKTHome.m` and `HKTSettings.m`**, read from the 21.44.4
  executable: the browse page's request method and `FEwhat_to_watch` identifier, the command
  event that opens a watch endpoint, and the Settings section calls. Each is looked up by name and
  compared by type encoding at launch. If a Settings member differs, nothing is hooked; if a Home
  member differs, Home stays native and the switch says the mode is not available.

## Limits

- A video opened from the web view skips the site's watch page, so the site does not add it to
  its History or count it as seen, and the like and dislike buttons on that page are out of reach.
- "Play all on YouTube" and other youtube.com links that are not a single video open outside the
  app.

## Build and checks

```sh
make -C HackerTube                                   # HackerTube/build/HackerTube.dylib
python3 HackerTube/tests/run.py /tmp/hackertube         # simulator checks, local fixture page
python3 HackerTube/tests/run.py /tmp/hackertube --live  # the same host against the live site
```

The library builds for arm64 iOS 17 with install name `@rpath/HackerTube.dylib`. The checks run
the library's sources in a throwaway simulator, where stand-in classes with YouTube's names
record what the app would be asked to do; they cover the web view, link routing, the failure
message and the hook logic. YouTube itself cannot run in a simulator, so the replaced Home tab and
playback are only proven on a phone.
