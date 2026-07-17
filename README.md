# music

Compact, mobile-friendly music player UI for Roblox. Plays audio IDs with a
draggable bar, a searchable track menu, volume control, and favorites.

## Run

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Ryshub/music/main/main.lua"))()
```

## Tracks

The song list lives in `tracks.lua` (loaded automatically). Add entries there:

```lua
{ genre = "Funk", name = "67 KID FUNK", artist = "DRIFTGØD", id = "84142247103485" },
```

Favorites are saved to `ryshub/music/favorites.json`.
