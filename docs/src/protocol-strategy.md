# Protocol strategy

Helmhost stays an RFB client. “VNC to everything” means a viewer that speaks extended RFB to stock servers, with later transports around that session. A second wire protocol is allowed only behind the session API that already exists, and only for agents Helmhost controls.

This note is a design record. It does not change the runtime.

**Recommendation.** V1-beta (L0 foundation and L1 viewer compatibility) is option A: extended RFB. The option C seam is already `helmhost_core::SessionFactory` and `ProtocolId`; it keeps a single RFB factory until a real second backend exists. Option B (a Helmhost wire protocol) waits for an owned agent and a measured gap that Tight, ZRLE, and optional H.264 leave open. Option D (cloud broker, relay, Guacamole-class gateway) is an L3 product that carries a session. It is a transport, and it lives outside `helmhost-rfb` and the hub.

## Options

| Option | Verdict |
|--------|---------|
| **A. RFB-first + extensions** | **Do this.** Connecting to TigerVNC, RealVNC, UltraVNC, QEMU, and other stock servers is the product. |
| **B. Custom wire protocol** | **Defer.** It helps only where both ends are Helmhost. Shipping it in V1-beta drops “connect to any VNC server.” |
| **C. One session API, many backends** | **Keep the seam.** Flutter already talks to `SessionHandle`. A new backend is a new factory, added when that backend can connect. |
| **D. Broker / gateway as the protocol** | **L3 transport only.** A relay forwards bytes. It does not replace the framebuffer encoding. |

## Limits of RFB

RFB (RFC 6143) sends pixels. RDP, X11, and SPICE can send drawing primitives, window structure, or glyphs, which is often cheaper for a still-structured UI. RFB’s advantage is that any desktop can be scraped into a framebuffer. Helmhost needs that advantage, so the viewer accepts the costs below.

- **Office UI vs video.** Tight and ZRLE, with CopyRect, fit text, windows, and idle desktops. Full-screen video and 3D re-send pixels every frame. The RFC has no motion-vector stream.
- **One socket.** Updates, input, clipboard, and any extension share one TCP connection. A large rectangle or a bulk transfer stalls input behind it.
- **Rectangle geometry.** Classic updates use 16-bit widths and heights. ExtendedDesktopSize (−308) covers multi-monitor layouts and client-driven resize on servers that implement it. Many servers still offer only DesktopSize (−223) or a fixed framebuffer.
- **Input model.** The pointer is a button mask plus coordinates. Keys are X keysyms. High-resolution wheels, touch, and IME are extensions.
- **Baseline security is the weak set** (None, VNC DES auth). Real protection is VeNCrypt, TigerVNC RSA-AES, or an outer tunnel such as SSH. V1-beta keeps those. It does not add a private cipher.
- **“RFB” is a family.** Audio, file transfer, and H.264 are outside the RFC. Two servers can both be “VNC” and share none of those features. Unknown encodings have to be skipped or the session dies.

## Extensions to use

### Already in the engine (L0 / L1)

`helmhost-rfb` already advertises and decodes the set below. L1 work is interop against real servers. A new codec is not required to call the beta done.

| Area | What the engine already speaks |
|------|--------------------------------|
| Pixels | Tight (7), ZRLE (16), CopyRect (1). Raw (0) on the LAN and balanced presets. Tight quality (−32..−23) and compress level (−256..−247) follow the bandwidth preset. |
| Geometry | DesktopSize (−223), ExtendedDesktopSize (−308), LastRect (−224) |
| Flow | ContinuousUpdates (−313) |
| Cursor | Cursor (−239), XCursor (−240), CursorWithAlpha (−314), VMware cursor and cursor position |
| Security | None, VNC auth, VeNCrypt subtypes 256–262 (Plain, TLS*, X509*), TigerVNC RA2 / RA2ne / RA2_256 / RA2ne_256 |
| Side channel | Bell, client and server cut text |

Advertised order stays Tight, then ZRLE, then Raw when the preset allows Raw. A server that ignores Tight still has ZRLE.

Hextile, TRLE, and standalone JPEG IDs exist as constants. They are not on the preferred list and are not part of the L1 bar.

### Optional modules (L2)

Each extension ships as its own module. The framebuffer reader dispatches to it. When the server does not offer it, the session stays on Tight and ZRLE.

| Extension | Role | Rule |
|-----------|------|------|
| H.264 (`0x48323634`, the LibVNC fourcc) | Video-like regions | Advertise only when a decoder is linked. Office content stays on Tight. In-RFB H.264 has a mixed record: keyframes and software decode often lose to Tight on UI, and many stock servers never send it. Keep it out of the pure-Rust L1 build. |
| QEMU audio (pseudo-encoding −259 / `0xFFFFFEFD`, client message 255) | VM guest audio | QEMU-only. Own module. Bound the audio queue; on overflow drop audio or disable it so pixels keep moving. |
| Extended clipboard (`0xC0A1E5CE`) | Beyond Latin-1 cut text | After basic cut text is solid across the L1 server set. |
| Fence (−307) | Explicit round-trip flow control | Only if ContinuousUpdates and the existing dirty coalescer are not enough. |

### Files stay off the pixel socket

There is no file-transfer standard that TigerVNC, RealVNC, UltraVNC, and QEMU share.

- UltraVNC uses client message type 7 and its own content types. That type is outside RFC 6143 (client messages 0–6) and is not the RealVNC mechanism.
- RealVNC file transfer is a separate, server-paired extension.
- Putting either dialect in `helmhost-rfb` ties the viewer to one server family and puts bulk bytes on the same socket as pixels and input.

**L2 file transfer is SFTP on the SSH tunnel.** The Beacon track (0.4) already names SSH / tunnel as its theme. The RFB session stays pixels, input, and clipboard. A file UI talks to the sidecar. An in-band RFB file extension comes back only for a named server that has no SSH and a written interop target.

## Custom protocol (option B)

A Helmhost wire protocol can carry a long-lived video stream (H.264 or AV1), a separate input channel, clipboard, and files, with a codec chosen for the content. NX, Jump, Parsec, Moonlight, and RDP show that this works when both ends are under one owner.

The costs are structural:

- Every third-party server still needs the RFB stack. B sits beside A.
- An agent or server has to be installed. That is a second product.
- Two protocols means two handshakes, two security reviews, and two interop suites.
- Folding RFB, video, files, audio, and the broker into one framing recreates the mega-protocol this split exists to avoid.

B starts only when all three are true:

1. Helmhost ships an agent it controls.
2. A recorded comparison — same office scene and same video scene — shows Tight/ZRLE and optional in-RFB H.264 miss a target that agent can hit.
3. The protocol is a second `SessionFactory` with a `ProtocolId` other than `"rfb"`, returning the same `SessionHandle` (framebuffer, pointer, key, clipboard, close). Flutter and FFI stay on `SessionCommand` and `SessionEvent`.

Until those are true, the tree does not grow opcodes, runtime crates, or feature flags for it.

## How the pieces sit

```text
Flutter UI  →  FFI  →  SessionHandle (helmhost-core)
                              ↑
                       SessionFactory
                      /                \
           RfbSessionFactory     (later) HelmSessionFactory
                      |                         |
           TCP / VeNCrypt / SSH tunnel          agent socket
                      |
           (L3) a broker may relay these bytes
```

- **L0–L2** construct only the RFB factory.
- **An L3 broker** authenticates the user, opens a path, and hands the viewer a host, a port, and a credential. The bytes on that path are still RFB. The hub does not absorb the gateway.
- **A later Helm factory** is a sibling crate that depends on `helmhost-core`, not on `helmhost-rfb`. Shared types are the framebuffer cache and the command/event enums. Pixel codecs stay in the protocol crate that decodes them.

`SessionCommand` and `SessionEvent` stay the remote-desktop surface: pointer, key, cut text, update request, resize, cursor, bell, disconnect. Audio samples and file progress become explicit variants when that module ships. A catch-all `Vendor(Vec<u8>)` would leak wire layout into the UI, so it is not part of the seam.

## Package boundaries

| Package | Owns | Leaves alone |
|---------|------|----------------|
| `helmhost-rfb` | Handshake, security types, encodings, the read/write loop | Broker accounts, a second protocol, Flutter |
| `helmhost-core` | `SessionFactory`, queues, framebuffer cache, registry, focus | Encoding byte layout |
| `helmhost-ffi` | Commands and events across the UI boundary | Choosing a wire format beyond which factory to call |
| Flutter `session`, `library`, `input` | Windows, credentials, input grab | Wire format |
| Future H.264, audio, SFTP modules | One extension each | The Tight decoder and the hub |
| Future L3 gateway crate | Relay, NAT traversal, cloud auth | Framebuffer decoding |

## Map onto L0–L3

These layers are the protocol plan. They do not rename the Lighthouse tracks in [versioning](./versioning.md) (Lantern, Range, Sector, Beacon, Buoy). Those tracks still ship on the versions already assigned.

| Layer | Protocol work | Done when |
|-------|----------------|-----------|
| **L0** Foundation | Keep the current engine: queues, RGBA framebuffer, Tight/ZRLE/Raw/CopyRect, resize, cursor, cut text, credentials redacted in logs | A session connects and paints through the existing factory |
| **L1** Viewer compatibility (V1-beta bar) | Interop with TigerVNC, RealVNC, UltraVNC, QEMU, and a libvnc-style server. Prefer VeNCrypt/X509 or RSA-AES when the server offers them; use classic VNC auth when that is the only choice. Skip unknown encodings | The same viewer opens those servers with no Helmhost agent |
| **L2** Quality on the same session | Optional H.264 module, QEMU audio module, extended clipboard, SFTP sidecar once the SSH tunnel exists | Each extension is negotiated. A server without it still runs as L1 |
| **L3** Transports and owned fleet | Broker/relay in its own package. A custom protocol only under the option B gate, as a second factory | The UI still opens a session by host, credentials, and protocol id |

L0 and L1 are the V1-beta contract. L2 items do not gate that contract. L3 does not move into the hub ahead of the wire.

## Non-goals

- A private cryptographic handshake for the beta. Use VeNCrypt, RSA-AES, or SSH.
- Replacing RFB with RDP, SPICE, NX, or a game-streaming stack.
- A dual-stack viewer in V1-beta, with RFB and a Helmhost protocol both live.
- One crate that speaks UltraVNC file transfer, RealVNC file transfer, and a Helmhost file channel.
- Carrying audio, files, or video on the pixel socket because the TCP connection is already up.
- A cloud gateway that terminates VNC and re-encodes it in order to make Helmhost faster. An L3 gateway forwards the session the client already speaks.
- Empty `ProtocolId` values and stub factories for protocols with nothing to connect to.
- Runtime changes in Flutter or Rust as part of adopting this note.

## Risks

| Risk | Response |
|------|----------|
| Vendor extensions accumulate inside the read loop | One module per extension. The loop dispatches or skips |
| H.264 pulls in a large decoder and a license question | Optional build, absent from L1 |
| QEMU audio is rare in the field | Ship against a QEMU fixture. Leave it off the default path |
| Bulk transfers block keyboard input | Files go over SFTP. Audio is bounded and droppable |
| `SessionEvent` turns into a grab bag | A new variant arrives with the module that emits it |
| A second protocol doubles QA | Start it only after the three option B gates hold |
| A broker “just” terminates VNC to be helpful | L3 forwards bytes. Decoding stays in `helmhost-rfb` |

## When to reopen option B

Before any option B crate, write a one-page measurement: TigerVNC with Tight and, if a server is available, in-RFB H.264, on one office scene and one video scene, recording bandwidth and frame interval. A small gap means the next investment is Tight quality, ContinuousUpdates, and the SSH sidecar. A large gap, together with an agent already on the product plan, is the signal to add factory number two.
