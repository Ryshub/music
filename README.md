# music

Compact, mobile-friendly music player UI for Roblox. Plays audio IDs with a
draggable bar, a searchable track menu, volume control, and favorites.

## Run

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Ryshub/music/main/main.lua"))()
```

## Components

`main.lua` loads its components automatically: `lib.lua` (shared UI/input/HTTP/icon
helpers) and `tracks.lua` (the song list). Add songs in `tracks.lua`:

```lua
{ genre = "Funk", name = "67 KID FUNK", artist = "DRIFTGØD", id = "84142247103485" },
```

Favorites are saved to `ryshub/music/favorites.json`.
