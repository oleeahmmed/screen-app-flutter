#include "flutter_window.h"

#include <optional>
#include <shellapi.h>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayCallbackMessage = WM_USER + 101;
constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayMenuOpen = 1001;
constexpr UINT kTrayMenuExit = 1002;

UINT TrayEvent(LPARAM lparam) {
  // NOTIFYICON_VERSION_4 packs the mouse message in the low word on 64-bit Windows.
  return LOWORD(lparam);
}

bool IsTrayActivateEvent(LPARAM lparam) {
  switch (TrayEvent(lparam)) {
    case WM_LBUTTONUP:
    case WM_LBUTTONDBLCLK:
    case NIN_SELECT:
    case NIN_KEYSELECT:
      return true;
    default:
      return false;
  }
}

bool IsTrayContextEvent(LPARAM lparam) {
  switch (TrayEvent(lparam)) {
    case WM_RBUTTONUP:
    case WM_RBUTTONDOWN:
    case WM_CONTEXTMENU:
      return true;
    default:
      return false;
  }
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();
  EnsureTrayIcon();
  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::EnsureTrayIcon() {
  HWND hwnd = GetHandle();
  if (!hwnd || tray_added_) {
    return;
  }

  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = hwnd;
  nid.uID = kTrayIconId;
  nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid.uCallbackMessage = kTrayCallbackMessage;
  nid.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(nid.szTip, L"Aims");
  if (Shell_NotifyIconW(NIM_ADD, &nid)) {
    tray_added_ = true;
    nid.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &nid);
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_added_) {
    return;
  }
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = GetHandle();
  nid.uID = kTrayIconId;
  Shell_NotifyIconW(NIM_DELETE, &nid);
  tray_added_ = false;
}

void FlutterWindow::RestoreFromTray() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }

  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  } else {
    ShowWindow(hwnd, SW_SHOW);
  }

  SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);

  HWND foreground = GetForegroundWindow();
  DWORD foreground_thread =
      foreground ? GetWindowThreadProcessId(foreground, nullptr) : 0;
  DWORD current_thread = GetCurrentThreadId();
  if (foreground_thread != 0 && foreground_thread != current_thread) {
    AttachThreadInput(current_thread, foreground_thread, TRUE);
  }

  BringWindowToTop(hwnd);
  SetForegroundWindow(hwnd);
  SetFocus(hwnd);

  if (foreground_thread != 0 && foreground_thread != current_thread) {
    AttachThreadInput(current_thread, foreground_thread, FALSE);
  }
}

void FlutterWindow::ShowTrayMenu() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }

  HMENU menu = CreatePopupMenu();
  MENUITEMINFOW open_item = {};
  open_item.cbSize = sizeof(open_item);
  open_item.fMask = MIIM_STRING | MIIM_ID | MIIM_STATE;
  open_item.fState = MFS_DEFAULT;
  open_item.wID = kTrayMenuOpen;
  open_item.dwTypeData = const_cast<LPWSTR>(L"Open Aims");
  InsertMenuItemW(menu, 0, TRUE, &open_item);
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayMenuExit, L"Exit");

  POINT cursor;
  GetCursorPos(&cursor);
  SetForegroundWindow(hwnd);
  const UINT selected = TrackPopupMenu(
      menu,
      TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY | TPM_VERTICAL,
      cursor.x, cursor.y, 0, hwnd, nullptr);
  DestroyMenu(menu);
  PostMessage(hwnd, WM_NULL, 0, 0);

  if (selected == kTrayMenuOpen) {
    RestoreFromTray();
  } else if (selected == kTrayMenuExit) {
    exiting_ = true;
    RemoveTrayIcon();
    Destroy();
    PostQuitMessage(0);
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  switch (message) {
    case WM_CLOSE:
      if (exiting_) {
        break;
      }
      ShowWindow(hwnd, SW_HIDE);
      return 0;
    case WM_CONTEXTMENU:
      if (tray_added_) {
        ShowTrayMenu();
        return 0;
      }
      break;
    case kTrayCallbackMessage:
      if (IsTrayActivateEvent(lparam)) {
        RestoreFromTray();
        return 0;
      }
      if (IsTrayContextEvent(lparam)) {
        ShowTrayMenu();
        return 0;
      }
      return 0;
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
