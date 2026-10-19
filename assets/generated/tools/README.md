# Fishing rod

Original Mystic Courier prop, extended from the existing authored primitive rod in
`scenes/props/tools/fishing_rod.tscn`. No vendor assets are changed. The playable
`data/items/fishing_rod.tres` equips this scene.

- Editable Godot primitive meshes with shared wood, cork, blue wrap and steel materials.
- Metres; about 1.9 m overall. Origin at grip centre, pole along +Y, reel/guides toward +Z.
- `Tip` is the attachment point used by ToolUser's fishing line.
- Three eight-sided line guides; fewer than 1000 triangles in total (checked in tests).
- `WorldCollision/Shape` is an inexpensive capsule. Collision is disabled while held to
  avoid pushing the courier. For a solid world prop, enable the shape and set the body's
  collision layer to 1. Decorative displays can leave collision off.
- Place, rotate or scale the scene root; keep the grip and Tip in their authored locations.

Authoring: edit this `.tscn` directly in Godot; all geometry is procedural and reusable.
