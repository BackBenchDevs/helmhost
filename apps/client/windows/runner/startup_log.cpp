#include "startup_log.h"

#include <windows.h>
#include <cstdio>

void LogStartupPhase(const wchar_t* phase) {
  wchar_t local_app_data[32768];
  const DWORD length = GetEnvironmentVariableW(
      L"LOCALAPPDATA", local_app_data, ARRAYSIZE(local_app_data));
  if (length == 0 || length >= ARRAYSIZE(local_app_data)) return;

  wchar_t path[32768];
  if (swprintf_s(path, ARRAYSIZE(path), L"%ls\\Helmhost", local_app_data) < 0) return;
  CreateDirectoryW(path, nullptr);
  if (swprintf_s(path, ARRAYSIZE(path), L"%ls\\Helmhost\\logs", local_app_data) < 0) return;
  CreateDirectoryW(path, nullptr);
  if (swprintf_s(path, ARRAYSIZE(path), L"%ls\\Helmhost\\logs\\startup.log", local_app_data) < 0) return;

  HANDLE file = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                            nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  LARGE_INTEGER size;
  if (GetFileSizeEx(file, &size) && size.QuadPart > 1024 * 1024) {
    SetFilePointer(file, 0, nullptr, FILE_BEGIN);
    SetEndOfFile(file);
  }
  SetFilePointer(file, 0, nullptr, FILE_END);
  SYSTEMTIME now;
  GetSystemTime(&now);
  wchar_t line[512];
  const int count = swprintf_s(
      line, ARRAYSIZE(line),
      L"%04u-%02u-%02uT%02u:%02u:%02u.%03uZ pid=%lu %ls\r\n",
      static_cast<unsigned>(now.wYear), static_cast<unsigned>(now.wMonth),
      static_cast<unsigned>(now.wDay), static_cast<unsigned>(now.wHour),
      static_cast<unsigned>(now.wMinute), static_cast<unsigned>(now.wSecond),
      static_cast<unsigned>(now.wMilliseconds), GetCurrentProcessId(), phase);
  if (count > 0) {
    char utf8[2048];
    const int bytes = WideCharToMultiByte(CP_UTF8, 0, line, count, utf8,
                                         static_cast<int>(sizeof(utf8)), nullptr,
                                         nullptr);
    if (bytes > 0) {
      DWORD written;
      WriteFile(file, utf8, static_cast<DWORD>(bytes), &written, nullptr);
      FlushFileBuffers(file);
    }
    OutputDebugStringW(line);
  }
  CloseHandle(file);
}

namespace {

LONG WINAPI StartupUnhandledExceptionFilter(EXCEPTION_POINTERS* info) {
  if (info && info->ExceptionRecord) {
    wchar_t phase[64];
    if (swprintf_s(phase, ARRAYSIZE(phase), L"exception code=0x%08lX",
                   static_cast<unsigned long>(
                       info->ExceptionRecord->ExceptionCode)) > 0) {
      LogStartupPhase(phase);
    }
  }
  return EXCEPTION_CONTINUE_SEARCH;
}

}  // namespace

void InstallStartupExceptionLogger() {
  SetUnhandledExceptionFilter(StartupUnhandledExceptionFilter);
}
