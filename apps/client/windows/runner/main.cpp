#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "startup_log.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  LogStartupPhase(L"process start");
  InstallStartupExceptionLogger();
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  {
    FlutterWindow window(project);
    Win32Window::Point origin(10, 10);
    Win32Window::Size size(1280, 720);
    if (!window.Create(L"helmhost", origin, size)) {
      LogStartupPhase(L"window creation failed");
      ::CoUninitialize();
      return EXIT_FAILURE;
    }
    LogStartupPhase(L"window created; entering message loop");
    window.SetQuitOnClose(true);

    ::MSG msg;
    while (::GetMessage(&msg, nullptr, 0, 0)) {
      ::TranslateMessage(&msg);
      ::DispatchMessage(&msg);
    }

    // Tear down the Flutter engine while COM is still initialized. Calling
    // CoUninitialize first can deliver COM callbacks into plugin state that is
    // still alive and abort with STATUS_FATAL_USER_CALLBACK_EXCEPTION.
    LogStartupPhase(L"message loop exited");
    window.Destroy();
    LogStartupPhase(L"window destroyed");
  }

  ::CoUninitialize();
  LogStartupPhase(L"com released");
  return EXIT_SUCCESS;
}
