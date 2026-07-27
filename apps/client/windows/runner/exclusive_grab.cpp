#include "exclusive_grab.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>

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

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;
HWND g_hwnd = nullptr;
HHOOK g_hook = nullptr;
std::atomic<bool> g_active{false};
std::atomic<bool> g_release_armed{false};
std::mutex g_mu;

bool IsRightControl(const KBDLLHOOKSTRUCT* info) {
  return info->vkCode == VK_RCONTROL ||
         (info->vkCode == VK_CONTROL && (info->flags & LLKHF_EXTENDED));
}

bool IsLeftControl(const KBDLLHOOKSTRUCT* info) {
  return info->vkCode == VK_LCONTROL ||
         (info->vkCode == VK_CONTROL && !(info->flags & LLKHF_EXTENDED));
}

uint32_t VkToKeysym(const KBDLLHOOKSTRUCT* info) {
  const DWORD vk = info->vkCode;
  if (IsRightControl(info)) return kXkControlR;
  if (IsLeftControl(info)) return kXkControlL;
  if (vk >= 'A' && vk <= 'Z') {
    return static_cast<uint32_t>(vk - 'A' + 0x61);
  }
  if (vk >= '0' && vk <= '9') {
    return static_cast<uint32_t>(vk);
  }
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
    case VK_OEM_1:
      return 0x003b;
    case VK_OEM_PLUS:
      return 0x003d;
    case VK_OEM_COMMA:
      return 0x002c;
    case VK_OEM_MINUS:
      return 0x002d;
    case VK_OEM_PERIOD:
      return 0x002e;
    case VK_OEM_2:
      return 0x002f;
    case VK_OEM_3:
      return 0x0060;
    case VK_OEM_4:
      return 0x005b;
    case VK_OEM_5:
      return 0x005c;
    case VK_OEM_6:
      return 0x005d;
    case VK_OEM_7:
      return 0x0027;
    case VK_INSERT:
      return 0xff63;
    default:
      return 0;
  }
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

void EmitKey(uint32_t keysym, bool down) {
  if (!g_channel || keysym == 0) {
    return;
  }
  flutter::EncodableMap args;
  args[flutter::EncodableValue("keysym")] =
      flutter::EncodableValue(static_cast<int32_t>(keysym));
  args[flutter::EncodableValue("down")] = flutter::EncodableValue(down);
  g_channel->InvokeMethod(
      "key", std::make_unique<flutter::EncodableValue>(args));
}

void EmitReleaseChord() {
  if (!g_channel) {
    return;
  }
  g_channel->InvokeMethod("releaseChord", nullptr);
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

  const uint32_t keysym = VkToKeysym(info);
  if (keysym != 0) {
    PostToUi([keysym, down] { EmitKey(keysym, down); });
  }
  return 1;
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
