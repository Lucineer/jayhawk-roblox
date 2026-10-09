# Jayhawk Rescue — Roblox

A Coast Guard helicopter rescue game set in Sitka Sound, Alaska. Rebuilt from the ground up for Roblox.

## The Game

You're a Jayhawk helicopter pilot at Sitka Coast Guard base. Distress calls come in — fishing boats on fire, ferries taking on water, cruise ships with medical emergencies. Fly out, hover over the vessel for 8 seconds, complete the rescue.

## Boats

- **Fishing boats** — engine fires, sinking
- **Ferries** — mechanical breakdown, medical emergency
- **Cruise ships** — medical emergency, man overboard
- **Sailboats** — capsized, lost rudder

## Sitka Setting

- Coast Guard base on Japonski Island
- Sitka Sound with Mount Edgecumbe
- Realistic Alaska maritime atmosphere

## Structure

```
src/
├── ServerScriptService/  # Server-side game logic (distress spawner, rescue validation)
├── StarterPlayerScripts/ # Client-side (helicopter controls, HUD, UI)
└── Workspace/            # Map layout (base, water, boats, landmarks)
docs/                     # Design docs
assets/                   # Models, images (imported into Studio)
```

## Status

🚧 Research phase — see `docs/` for the build plan.
