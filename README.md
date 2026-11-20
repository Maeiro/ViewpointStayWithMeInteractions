# Stay With Me Viewpoint Interactions

A client-side mod that shows the Stay With Me companion menu in Project Viewpoint's native interaction panel.

## Requirements

- Project Zomboid Build 42.22 or newer
- Project Viewpoint 0.1.7 (the supported interaction classes are checked when the game runs)
- Stay With Me
- ZombieBuddy

## Install

Place the mod folder in the local Workshop layout so the files are under:

```text
%UserProfile%\Zomboid\Workshop\Stay With Me Viewpoint Interactions\Contents\mods\ViewpointStayWithMeInteractions\
```

Copy `ViewpointStayWithMeInteractions` from this project's `content\mods` folder. Keep both `mod.info` files: the one at the mod root and the one inside `42`.

## Use

Enable the mod, restart Project Zomboid, and approve its Java component in ZombieBuddy if prompted. In first- or third-person Viewpoint mode, stand within a couple of tiles of your companion and aim at them. Use the mouse wheel to move through entries and **F** to choose an action or open a submenu. Submenus have a **Back** option at the top.

## Notes

ZombieBuddy applies the compatibility hooks when the game starts. The mod leaves the original Viewpoint and Stay With Me files intact. On an unmatched Viewpoint build, the mod uses its separate Lua menu when the Viewpoint Lua mirror is available.

## In-game check

Look for `[Stay With Me Viewpoint Interactions] Native interaction panel active` in `console.txt`. Aim at the companion, open **Talk**, scroll upward from the top to reach the last selectable option, and press **F** on **Back** to return. Aim at another object nearby to check its regular interactions.

## Build and Workshop layout

Run `tools/Build.ps1` with JDK 25. Pass `-JdkDir`, `-GameDir`, and `-ZombieBuddyJar` if they are installed elsewhere. For SteamCMD, point `contentfolder` at this project's `content` folder. It contains the complete `mods\ViewpointStayWithMeInteractions` payload for the current 0.2.1 release.
