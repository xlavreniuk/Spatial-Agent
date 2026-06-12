# Universal AI Repair AR Assistant

## Goal

Build a mobile app where the user points the camera at an object, speaks naturally, receives structured repair guidance from Gemini, and sees stable AR indicators attached to real-world anchors.

## Current App Direction

The current prototype is native iOS with SwiftUI, ARKit, and RealityKit. Keep this path for the MVP unless the project explicitly migrates to Flutter or React Native later.

ARKit owns:

- World tracking
- Anchors
- Plane detection
- Object placement

Gemini owns:

- Voice conversation
- Reasoning
- Procedure generation
- Part identification
- Troubleshooting

Gemini must not output raw AR coordinates. It should output semantic instructions such as `UNSCREW bolt_1`; the app renderer maps that instruction to a detected object and creates the AR anchor.

## Instruction Contract

Gemini responses should use this shape:

```json
{
  "step": 1,
  "voice": "Unscrew the highlighted bolts.",
  "instructions": [
    {
      "action": "UNSCREW",
      "target": "bolt_1"
    }
  ]
}
```

Allowed actions:

- `UNSCREW`
- `TIGHTEN`
- `PULL`
- `PUSH`
- `LIFT`
- `LOWER`
- `OPEN`
- `CLOSE`
- `SLIDE_LEFT`
- `SLIDE_RIGHT`
- `REMOVE`
- `INSTALL`
- `ROTATE_CW`
- `ROTATE_CCW`
- `CHECK`
- `WARNING`
- `COMPLETE`

## Renderer Flow

```text
Gemini instruction JSON
Vision object list
Renderer resolves target object
ARKit creates anchor
RealityKit attaches 3D indicator
RealityKit plays action animation
```

## MVP Build Order

1. Camera and AR scene
2. Voice input
3. Gemini instruction generation
4. Object detection
5. SVG icon pack
6. SVG to GLB conversion
7. Anchored AR placement
8. Instruction JSON renderer
9. Voice output
10. Repair database

## Production Note

The local `.env` Gemini key path is prototype-only. Before public release, move Gemini calls behind a backend so the real API key never ships inside the app.
