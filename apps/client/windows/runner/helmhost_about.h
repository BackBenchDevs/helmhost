#ifndef RUNNER_HELMHOST_ABOUT_H_
#define RUNNER_HELMHOST_ABOUT_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include <windows.h>

// MethodChannel helmhost/app — Help→About asks Dart to show the Flutter dialog.
class HelmhostAbout {
 public:
  static void Attach(flutter::BinaryMessenger* messenger, HWND hwnd);
  static void ShowFromFlutter(HWND hwnd);

 private:
  static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      channel_;
  static HWND hwnd_;
};

#endif  // RUNNER_HELMHOST_ABOUT_H_
