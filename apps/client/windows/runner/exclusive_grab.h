#ifndef RUNNER_EXCLUSIVE_GRAB_H_
#define RUNNER_EXCLUSIVE_GRAB_H_

#include <flutter/binary_messenger.h>

#include <windows.h>

// WH_KEYBOARD_LL exclusive grab → MethodChannel helmhost/exclusive_grab.
class ExclusiveGrab {
 public:
  static void Attach(flutter::BinaryMessenger* messenger, HWND hwnd);
  static void Detach();

 private:
  ExclusiveGrab() = delete;
};

// Drain UI-thread callbacks posted from the low-level hook (WM_APP+40).
bool ExclusiveGrabHandleAppMessage(HWND hwnd, UINT message, WPARAM wParam,
                                   LPARAM lParam);

#endif  // RUNNER_EXCLUSIVE_GRAB_H_
