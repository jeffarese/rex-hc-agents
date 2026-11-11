# The README's demo

The [video](../media/demo.mp4) on the [README](../../README.md) is one real run of the plugin in Rex for
Mac, on a stage that is synthetic from end to end. Nothing in it comes from a real project, session or
person.

**Real:** Rex (the app and its server), herdr-core, and this repository's plugin: the manager that opens a
tab for each agent, `hc attach` in each tab, and the statuses Rex shows in its sidebar.

**Synthetic:**

- **The agents.** [bin/claude](bin/claude) is a script, started by `hc run` as Claude Code would be. It
  reports its status with OSC 7501 as Claude Code does (working, blocked on a permission, done) and draws a
  screen modelled on Claude Code's. The files it reads and the tests it runs don't exist. It never calls a
  model.
- **The project.** `~/code/shop` is an empty folder.
- **The machine.** herdr-core and the Rex server run with a home, config and state of their own in one
  folder under `/tmp`. The Rex app in the video is a second one whose home is that folder, so "This Mac" in
  its sidebar is the stage's server.

Nothing of yours is read or written, and your own sessions and agents don't show.

## Record it again

```sh
sh docs/demo/record.sh
```

It needs Rex for Mac, herdr-core, ffmpeg, python3 and
[cua-driver](https://github.com/trycua/cua), and the terminal it runs in needs the Screen Recording
permission.

- **[stage.sh](stage.sh)** starts the stage's herdr-core and Rex server and prints the stage's folder.
  `stage.sh --down <folder>` stops everything and deletes it.
- **[record.sh](record.sh)** builds the stage, opens the second Rex app, plays the scene, encodes
  `docs/media/demo.mp4` (H.264) and `demo.gif` (10 fps, 960 px wide), and takes the stage down.
- **[scene.py](scene.py)** plays the scene: it types into the shop's shell with the `rex` CLI and clicks
  the sidebar with cua-driver, while it saves the window ten times a second.

Two things to know before you run it:

- **The second Rex app shares your Rex app's settings.** The scene limits its sidebar to "This Mac", so
  your other hosts stay out of the picture.
- **Its window comes to the front once,** when it opens. After that the scene runs in the background.
