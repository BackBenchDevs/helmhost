#ifndef RUNNER_SESSION_PLUGIN_REGISTRANT_H_
#define RUNNER_SESSION_PLUGIN_REGISTRANT_H_

#include <flutter/plugin_registry.h>

// Plugins for desktop_multi_window secondary engines.
// Skips AutoUpdaterWindows — WinSparkle is a process-wide singleton.
void RegisterSessionPlugins(flutter::PluginRegistry* registry);

#endif  // RUNNER_SESSION_PLUGIN_REGISTRANT_H_
