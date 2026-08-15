DRISHTI V5 — NATIVE PHYSICS PROTOTYPE
=====================================

This is a fresh native macOS rebuild. It is not HTML/WebView.

WHAT YOU SHOULD SEE
- Double-click Drishti V5.app.
- Only a realistic plain pumpkin/ash-gourd with burning camphor appears.
- No app panel, text, counter, instructions, buttons, borders, or background.
- The browser/photo/social-media screen underneath remains visible.

MOUSE EXPERIENCE
- No click is required.
- When the mouse pointer touches the pumpkin, the pumpkin attaches automatically.
- It follows with spring/inertia so it has weight instead of being rigidly glued to the pointer.
- You can move clockwise, anticlockwise, randomly, one round, ten rounds, or no rounds.

BOTTOM IMPACT
- Drag the pumpkin toward the bottom.
- Near the bottom it releases into gravity.
- It physically hits the bottom edge and shatters.
- Pieces, fragments, and seeds use SpriteKit physics: they bounce, rotate, collide, and settle.
- The flame/smoke disappears on impact.
- Debris stays on the bottom for about 3 seconds.
- Debris fades and the app closes automatically.

IMPORTANT
The transparent overlay ignores mouse clicks, so the app underneath can still receive clicks.
The Drishti app only watches the current mouse location to detect when the pointer touches the pumpkin.

ONE-TIME BUILD
1. Unzip the package.
2. Double-click Build_Drishti_V5_Mac.command.
3. The script creates "Drishti V5.app" on your Desktop.
4. After that, use the app directly by double-clicking it.

Apple Command Line Tools are needed only for that one-time compilation. Xcode does not have to stay open while using the app.

This build targets macOS 13+.
