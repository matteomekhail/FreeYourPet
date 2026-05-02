# AlwaysPet

AlwaysPet is a tiny native macOS desktop pet host that runs your installed Codex pet independently of Codex.

It loads the active Codex pet package from `~/.codex/pets`, renders the standard Codex `1536x1872` sprite atlas, keeps a small menu-bar control, and includes a LaunchAgent installer so it can start when you log in.

## Controls

- Drag the pet to move it.
- Double-click the pet to wave.
- Use the menu-bar item named after your Codex pet to pause wandering, trigger states, resize, center, toggle always-on-top mode, choose another pet, or quit.
- Choose Pet opens a native picker UI that scans `~/.codex/pets`, previews installed pets, and saves the selected pet for the next login.