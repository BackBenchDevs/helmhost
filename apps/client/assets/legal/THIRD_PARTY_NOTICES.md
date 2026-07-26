# Third-party notices — Helmhost

**Helmhost is not open source.** The product, architecture, and core engines
are proprietary software of **BackBenchDevs**, licensed only under the
BackBenchDevs Proprietary Software License (Licenses → Helmhost in the app,
or `LICENSE` / `assets/legal/LICENSE.txt` in the source tree).

This page lists **third-party** open-source components that may be linked or
shipped with Helmhost. They remain under their own licenses. Your build may
not include every component below (platform and features differ).

**Rights:** Copyrights, trademarks, and other rights in third-party
components and marks named here belong to their respective owners and
licensors. Helmhost and BackBenchDevs do **not** claim those rights. Names
are used only for identification and license compliance.

---

## Summary of major components

| Component | Typical license (SPDX) | Role |
|-----------|------------------------|------|
| Flutter / Dart SDK * | BSD-3-Clause | UI toolkit |
| cupertino_icons | MIT | Icons |
| ffi | BSD-3-Clause | Dart FFI |
| path_provider | BSD-3-Clause | Paths |
| desktop_multi_window | MIT | Multi-window |
| window_manager | MIT | Window chrome |
| shared_preferences | BSD-3-Clause | Settings |
| file_picker | MIT | File dialogs |
| image (Dart) | MIT | Thumbnails / images |
| auto_updater | MIT | Update glue |
| http | BSD-3-Clause | HTTP |
| path | BSD-3-Clause | Path utils |
| tokio | MIT | Async runtime (Rust) |
| serde / serde_json | MIT OR Apache-2.0 | Serialization |
| rustls / tokio-rustls | Apache-2.0 / MIT / ISC | TLS |
| ring | ISC-style | Crypto |
| webpki-roots | MPL-2.0 | TLS trust roots (crate) |
| flate2 | MIT OR Apache-2.0 | Compression |
| des / cipher | MIT OR Apache-2.0 | VNC DES auth |
| image (Rust) | MIT OR Apache-2.0 | JPEG decode |
| tracing / tracing-subscriber | MIT | Logging |
| once_cell | MIT OR Apache-2.0 | Lazy init |
| Sparkle * | MIT | macOS updates |
| WinSparkle * | MIT | Windows updates |

\* Third-party name / mark — rights remain with the respective owners;
BackBenchDevs does not claim them. Listed for attribution and compliance.

---

## Dependency licenses (excerpt)

### MPL-2.0 — webpki-roots

The Rust crate **webpki-roots** (TLS certificate trust anchors) is licensed
under SPDX **MPL-2.0** (Mozilla Public License 2.0 * — name of that license;
rights in the license and any related marks remain with their owners;
BackBenchDevs does not claim them).

- Full text: https://www.mozilla.org/MPL/2.0/
- Covered source: upstream `webpki-roots` and the Helmhost dependency tree
  (`Cargo.lock`)

### MIT License (representative text)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

Applies in whole or in part to many Dart and Rust dependencies listed above,
and to **Sparkle** * / **WinSparkle** * (rights remain with their respective
copyright holders; BackBenchDevs does not claim them).

#### Sparkle * — required copyright attribution

Copyright © 2006-2013 Andy Matuschak.
Copyright © 2009-2013 Elgato Systems GmbH.
Copyright © 2011-2014 Kornel Lesiński.
Copyright © 2015-2017 Mayur Pawashe.
Copyright © 2014 C.W. Betts.
Copyright © 2014 Petroules Corporation.
Copyright © 2014 Big Nerd Ranch.
All rights reserved.

(MIT — see text above. BackBenchDevs does not claim copyright in Sparkle.)

#### WinSparkle * — required copyright attribution

Copyright © Vaclav Slavik and contributors.
(MIT — see upstream project and text above. BackBenchDevs does not claim
copyright in WinSparkle.)

### BSD 3-Clause License (representative text)

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Applies in whole or in part to the Flutter / Dart SDK * and several packages
(path_provider, shared_preferences, http, and others). Those names and
related marks remain with their respective owners; BackBenchDevs does not
claim them.

### Apache-2.0

Full text: https://www.apache.org/licenses/LICENSE-2.0

Some Rust crates (for example parts of the rustls / serde dual-license set)
are available under Apache-2.0 and/or MIT. Where Apache-2.0 applies, the
NOTICE and license terms of those crates apply. Apache and related marks
remain with their respective owners; BackBenchDevs does not claim them.

### ring (ISC-style) — required copyright attribution

Copyright © 2015-2025 Brian Smith and contributors.

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION
OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

Additional copyright notices for assembly and third-party code within ring
appear in the upstream crate. BackBenchDevs does not claim copyright in
ring.

---

## Rights and marks

- Third-party copyrights and trademarks (including platform store marks and
  toolkit names) remain the property of their respective owners. They are
  mentioned only for identification and license compliance. Helmhost /
  BackBenchDevs do not claim those rights.
- “Helmhost” and “BackBenchDevs” are names used by BackBenchDevs for this
  product and organization. They are not asserted here as registered
  trademarks. Do not use them to brand competing products without written
  permission from BackBenchDevs.
