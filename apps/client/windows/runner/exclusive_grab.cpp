#include "exclusive_grab.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <unordered_map>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

namespace {

constexpr char kChannelName[] = "helmhost/exclusive_grab";

constexpr uint32_t kXkControlL = 0xffe3;
constexpr uint32_t kXkControlR = 0xffe4;
constexpr uint32_t kXkShiftL = 0xffe1;
constexpr uint32_t kXkShiftR = 0xffe2;
constexpr uint32_t kXkAltL = 0xffe9;
constexpr uint32_t kXkAltR = 0xffea;
constexpr uint32_t kXkSuperL = 0xffeb;
constexpr uint32_t kXkSuperR = 0xffec;
constexpr uint32_t kXkEscape = 0xff1b;
constexpr uint32_t kXkTab = 0xff09;
constexpr uint32_t kXkBackSpace = 0xff08;
constexpr uint32_t kXkReturn = 0xff0d;
constexpr uint32_t kXkSpace = 0x0020;
constexpr uint32_t kXkDelete = 0xffff;
constexpr uint32_t kXkHome = 0xff50;
constexpr uint32_t kXkEnd = 0xff57;
constexpr uint32_t kXkPageUp = 0xff55;
constexpr uint32_t kXkPageDown = 0xff56;
constexpr uint32_t kXkLeft = 0xff51;
constexpr uint32_t kXkUp = 0xff52;
constexpr uint32_t kXkRight = 0xff53;
constexpr uint32_t kXkDown = 0xff54;
constexpr uint32_t kXkInsert = 0xff63;

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;
HWND g_hwnd = nullptr;
HHOOK g_hook = nullptr;
std::atomic<bool> g_active{false};
std::atomic<bool> g_release_armed{false};
std::mutex g_mu;
// vk → keysym of last press (ToUnicodeEx often returns 0 on key-up).
std::unordered_map<DWORD, uint32_t> g_down_keysyms;

bool IsRightControl(const KBDLLHOOKSTRUCT* info) {
  return info->vkCode == VK_RCONTROL ||
         (info->vkCode == VK_CONTROL && (info->flags & LLKHF_EXTENDED));
}

bool IsLeftControl(const KBDLLHOOKSTRUCT* info) {
  return info->vkCode == VK_LCONTROL ||
         (info->vkCode == VK_CONTROL && !(info->flags & LLKHF_EXTENDED));
}

uint32_t UcsToKeysym(uint32_t u) {
  if (u >= 0x20 && u <= 0x7e) return u;
  if (u >= 0xa0 && u <= 0xff) return u;
  return 0x01000000u | u;
}

/// Non-printable / modifier map (TigerVNC vkey_map style).
uint32_t SpecialVkToKeysym(const KBDLLHOOKSTRUCT* info) {
  const DWORD vk = info->vkCode;
  if (IsRightControl(info)) return kXkControlR;
  if (IsLeftControl(info)) return kXkControlL;
  switch (vk) {
    case VK_LSHIFT:
    case VK_SHIFT:
      return kXkShiftL;
    case VK_RSHIFT:
      return kXkShiftR;
    case VK_LMENU:
      return kXkAltL;
    case VK_RMENU:
      return kXkAltR;
    case VK_MENU:
      return (info->flags & LLKHF_EXTENDED) ? kXkAltR : kXkAltL;
    case VK_LWIN:
      return kXkSuperL;
    case VK_RWIN:
      return kXkSuperR;
    case VK_ESCAPE:
      return kXkEscape;
    case VK_TAB:
      return kXkTab;
    case VK_BACK:
      return kXkBackSpace;
    case VK_RETURN:
      return kXkReturn;
    case VK_SPACE:
      return kXkSpace;
    case VK_DELETE:
      return kXkDelete;
    case VK_HOME:
      return kXkHome;
    case VK_END:
      return kXkEnd;
    case VK_PRIOR:
      return kXkPageUp;
    case VK_NEXT:
      return kXkPageDown;
    case VK_LEFT:
      return kXkLeft;
    case VK_UP:
      return kXkUp;
    case VK_RIGHT:
      return kXkRight;
    case VK_DOWN:
      return kXkDown;
    case VK_INSERT:
      return kXkInsert;
    case VK_F1:
      return 0xffbe;
    case VK_F2:
      return 0xffbf;
    case VK_F3:
      return 0xffc0;
    case VK_F4:
      return 0xffc1;
    case VK_F5:
      return 0xffc2;
    case VK_F6:
      return 0xffc3;
    case VK_F7:
      return 0xffc4;
    case VK_F8:
      return 0xffc5;
    case VK_F9:
      return 0xffc6;
    case VK_F10:
      return 0xffc7;
    case VK_F11:
      return 0xffc8;
    case VK_F12:
      return 0xffc9;
    default:
      return 0;
  }
}

uint32_t ResolveKeysym(const KBDLLHOOKSTRUCT* info) {
  if (const uint32_t special = SpecialVkToKeysym(info)) {
    return special;
  }
  BYTE state[256];
  if (!GetKeyboardState(state)) {
    return 0;
  }
  // Clear Ctrl so Ctrl+letter yields the letter, not a control code.
  state[VK_CONTROL] = 0;
  state[VK_LCONTROL] = 0;
  state[VK_RCONTROL] = 0;
  WCHAR buf[4] = {};
  const HKL hkl = GetKeyboardLayout(0);
  const UINT scan = MapVirtualKeyExW(info->vkCode, MAPVK_VK_TO_VSC, hkl);
  const int n =
      ToUnicodeEx(info->vkCode, scan, state, buf, 4, 0, hkl);
  if (n > 0) {
    const uint32_t u = static_cast<uint32_t>(buf[0]);
    if (u >= 0x20 && !(u >= 0x7f && u < 0xa0)) {
      return UcsToKeysym(u);
    }
  }
  // Dead-key / no mapping: do not invent a US fallback — pass through to host.
  return 0;
}

void PostToUi(std::function<void()> fn) {
  if (!g_hwnd) {
    return;
  }
  auto* heap_fn = new std::function<void()>(std::move(fn));
  if (!PostMessageW(g_hwnd, WM_APP + 40, 0,
                    reinterpret_cast<LPARAM>(heap_fn))) {
    delete heap_fn;
  }
}

void EmitKey(uint32_t keysym, bool down, uint32_t physical) {
  if (!g_channel || keysym == 0) {
    return;
  }
  flutter::EncodableMap args;
  args[flutter::EncodableValue("keysym")] =
      flutter::EncodableValue(static_cast<int32_t>(keysym));
  args[flutter::EncodableValue("down")] = flutter::EncodableValue(down);
  args[flutter::EncodableValue("physical")] =
      flutter::EncodableValue(static_cast<int32_t>(physical));
  g_channel->InvokeMethod(
      "key", std::make_unique<flutter::EncodableValue>(args));
}

void EmitReleaseChord() {
  if (!g_channel) {
    return;
  }
  g_channel->InvokeMethod("releaseChord", nullptr);
}

void EmitLocalShortcut(const char* kind) {
  if (!g_channel) {
    return;
  }
  flutter::EncodableMap args;
  args[flutter::EncodableValue("kind")] = flutter::EncodableValue(kind);
  g_channel->InvokeMethod(
      "localShortcut", std::make_unique<flutter::EncodableValue>(args));
}

/// Viewer-local paste/consume under exclusive grab (not bare Control chords).
const char* LocalShortcutKind(const KBDLLHOOKSTRUCT* info) {
  const bool shift = (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;
  const bool control = (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
  const bool alt = (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
  const bool meta = (GetAsyncKeyState(VK_LWIN) & 0x8000) != 0 ||
                    (GetAsyncKeyState(VK_RWIN) & 0x8000) != 0;
  const DWORD vk = info->vkCode;

  // Ctrl+Alt+V — explicit viewer paste (Win+V is OS clipboard history).
  if (control && alt && !meta && !shift && (vk == 'V' || vk == 'v')) {
    return "paste";
  }

  // Never steal bare Control chords — those are for the remote.
  if (control && !meta && !alt) {
    return nullptr;
  }
  if (shift && !meta && !control && vk == VK_INSERT) {
    return "paste";
  }
  if (meta && (vk == 'C' || vk == 'c' || vk == 'X' || vk == 'x')) {
    return "consume";
  }
  return nullptr;
}

LRESULT CALLBACK LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) {
  if (nCode != HC_ACTION || !g_active.load()) {
    return CallNextHookEx(g_hook, nCode, wParam, lParam);
  }
  const auto* info = reinterpret_cast<KBDLLHOOKSTRUCT*>(lParam);
  const bool down = wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN;
  const bool up = wParam == WM_KEYUP || wParam == WM_SYSKEYUP;
  if (!down && !up) {
    return CallNextHookEx(g_hook, nCode, wParam, lParam);
  }

  if (IsRightControl(info)) {
    if (down) {
      g_release_armed.store(true);
    } else if (up && g_release_armed.exchange(false)) {
      PostToUi([] { EmitReleaseChord(); });
    }
    return 1;
  }
  if (down) {
    g_release_armed.store(false);
  }

  if (down) {
    if (const char* kind = LocalShortcutKind(info)) {
      PostToUi([kind] { EmitLocalShortcut(kind); });
      return 1;
    }
  }

  const DWORD vk = info->vkCode;
  uint32_t keysym = 0;
  if (down) {
    keysym = ResolveKeysym(info);
    if (keysym != 0) {
      std::lock_guard<std::mutex> lock(g_mu);
      g_down_keysyms[vk] = keysym;
    }
  } else {
    std::lock_guard<std::mutex> lock(g_mu);
    const auto it = g_down_keysyms.find(vk);
    if (it != g_down_keysyms.end()) {
      keysym = it->second;
      g_down_keysyms.erase(it);
    } else {
      keysym = ResolveKeysym(info);
    }
  }

  if (keysym != 0) {
    const uint32_t physical = vk;
    PostToUi([keysym, down, physical] { EmitKey(keysym, down, physical); });
    return 1;
  }
  // Unmapped: pass to host so keys are not eaten silently.
  return CallNextHookEx(g_hook, nCode, wParam, lParam);
}

void StartHook() {
  if (g_hook) {
    return;
  }
  g_release_armed.store(false);
  g_hook = SetWindowsHookExW(WH_KEYBOARD_LL, LowLevelKeyboardProc, nullptr, 0);
  g_active.store(g_hook != nullptr);
}

void StopHook() {
  g_active.store(false);
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_down_keysyms.clear();
  }
  if (g_hook) {
    UnhookWindowsHookEx(g_hook);
    g_hook = nullptr;
  }
  g_release_armed.store(false);
}

}  // namespace

bool ExclusiveGrabHandleAppMessage(HWND /*hwnd*/, UINT message,
                                   WPARAM /*wParam*/, LPARAM lParam) {
  if (message != WM_APP + 40) {
    return false;
  }
  auto* fn = reinterpret_cast<std::function<void()>*>(lParam);
  if (fn) {
    (*fn)();
    delete fn;
  }
  return true;
}

void ExclusiveGrab::Attach(flutter::BinaryMessenger* messenger, HWND hwnd) {
  std::lock_guard<std::mutex> lock(g_mu);
  g_hwnd = hwnd;
  g_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        const auto& method = call.method_name();
        if (method == "start") {
          StartHook();
          if (g_hook) {
            result->Success();
          } else {
            result->Error("hook_failed", "SetWindowsHookEx failed");
          }
        } else if (method == "stop") {
          StopHook();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

void ExclusiveGrab::Detach() {
  std::lock_guard<std::mutex> lock(g_mu);
  StopHook();
  g_channel.reset();
  g_hwnd = nullptr;
}
