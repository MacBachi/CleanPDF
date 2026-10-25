// CleanPDF — turn untrusted PDFs into guaranteed-passive, safe PDFs.
// Copyright (C) 2026 CleanPDF contributors
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. This program is distributed WITHOUT ANY WARRANTY; see
// the GNU General Public License <https://www.gnu.org/licenses/> for details.

#ifndef CISOLATION_H
#define CISOLATION_H

#include <stdint.h>
#include <sys/types.h>

/// Applies an SBPL sandbox profile to the calling process. Irreversible.
/// Returns 0 on success. On failure returns -1 and, if `error_out` is not
/// NULL, stores a malloc'd message there that the caller must free().
int cleanpdf_apply_sandbox(const char *profile, char **error_out);

/// Physical memory footprint of process `pid` in bytes, or -1 on error.
int64_t cleanpdf_phys_footprint(pid_t pid);

/// Hard limits for the worker: no core dumps of untrusted data, and a CPU
/// time ceiling (seconds) after which the kernel stops the process.
void cleanpdf_limit_worker_resources(uint64_t cpu_seconds);

#endif
