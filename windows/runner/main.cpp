#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
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

  // Lancement automatique pour un enregistrement prevu (tache Windows) :
  // fenetre reduite, et rien a faire si Canalix tourne deja.
  bool background = false;
  for (const auto& a : command_line_arguments) {
    if (a == "--background") background = true;
  }
  HANDLE single = ::CreateMutexW(nullptr, TRUE, L"Local\\CanalixPlayerSingleInstance");
  if (single != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    if (!background) {
      HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Canalix");
      if (existing) {
        ::ShowWindow(existing, SW_RESTORE);
        ::SetForegroundWindow(existing);
      }
    }
    return EXIT_SUCCESS;
  }
  Win32Window::SetStartMinimized(background);

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Canalix", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
