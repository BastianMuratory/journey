# Journey

A Pokémon-like game I'm making in Godot 4.4. It's still very early, most of it
is prototype code, but the base is there.

Rough idea: you have a base camp, you pick a team, you send them into a level,
they fight on their own, and you come back with new stuff. Something in the
spirit of Pokémon Quest.

## What's in it

* A main menu, a base camp and a level, with a small scene manager to move
  between them.
* Around 370 species with their data (types, base stats, evolutions, learnable
  moves) and their 3D models, plus a bit more than 200 moves.
* A Pokedex that keeps track of what you've seen and caught. It saves to disk.
* A level that builds itself: random grid, random enemies, allies that walk and
  attack by themselves.
* Procedural animations. The models are static .obj files with no bones, so
  idle, run and the squash and stretch are all computed in code. Each species
  has a body type (biped, quadruped, hover, flyer, serpentine) which decides
  how it moves.
* A mega evolution shader effect. It works but it's not plugged into anything
  right now.
* An admin menu to browse every species one by one, useful to check models and
  animations.

## Running it

You need Godot 4.4 (mobile renderer). Open the folder in the editor and press
F5. There's nothing else to install.

## Folders

* `game_scenes/` the scenes: main menu, base camp, level, pokedex, admin menu
* `logic/` the data and the rules: species, moves, player, collection
* `systems/` shaders and visual effects
* `assets/` models, textures and icons

## Not done yet

Teams and the collection aren't really wired up, so the level always spawns the
same allies. The fights have no win or lose screen. Nothing is saved except the
pokedex. There is no sound at all.
