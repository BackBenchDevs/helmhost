#include "helmhost_about.h"

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
    HelmhostAbout::channel_;
HWND HelmhostAbout::hwnd_ = nullptr;

void HelmhostAbout::Attach(flutter::BinaryMessenger* messenger, HWND hwnd) {
  hwnd_ = hwnd;
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "helmhost/app",
      &flutter::StandardMethodCodec::GetInstance());
  // Dart owns the About UI; native only invokes showAbout from the menu.
  channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& /*call*/,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) { result->NotImplemented(); });
}

void HelmhostAbout::ShowFromFlutter(HWND /*hwnd*/) {
  if (!channel_) {
    return;
  }
  channel_->InvokeMethod("showAbout", nullptr);
}
