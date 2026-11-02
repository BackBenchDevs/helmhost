#ifndef RUNNER_STARTUP_LOG_H_
#define RUNNER_STARTUP_LOG_H_

// Best-effort diagnostics; accepts fixed phase names, never credentials.
void LogStartupPhase(const wchar_t* phase);

// Logs unhandled exception codes, then continues the default search.
void InstallStartupExceptionLogger();

#endif  // RUNNER_STARTUP_LOG_H_
