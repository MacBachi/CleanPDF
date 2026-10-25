// CleanPDF — turn untrusted PDFs into guaranteed-passive, safe PDFs.
// Copyright (C) 2026 CleanPDF contributors
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. This program is distributed WITHOUT ANY WARRANTY; see
// the GNU General Public License <https://www.gnu.org/licenses/> for details.

#include "cisolation.h"

#include <libproc.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>

// sandbox.h is marked deprecated, but sandbox_init remains the only public
// entry point for applying a sandbox profile to a running process.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#include <sandbox.h>

int cleanpdf_apply_sandbox(const char *profile, char **error_out) {
    char *err = NULL;
    // flags = 0 makes `profile` SBPL source rather than a predefined profile
    // name. The header documents only SANDBOX_NAMED; profile text has long
    // been relied on regardless (Chromium did so for years). CleanPDF fails
    // closed if this ever stops working, and its test suite verifies that the
    // sandbox is actually enforced.
    if (sandbox_init(profile, 0, &err) == 0) {
        return 0;
    }
    if (error_out != NULL) {
        *error_out = strdup(err != NULL ? err : "sandbox_init failed");
    }
    if (err != NULL) {
        sandbox_free_error(err);
    }
    return -1;
}
#pragma clang diagnostic pop

int64_t cleanpdf_phys_footprint(pid_t pid) {
    struct rusage_info_v4 info;
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&info) != 0) {
        return -1;
    }
    return (int64_t)info.ri_phys_footprint;
}

void cleanpdf_limit_worker_resources(uint64_t cpu_seconds) {
    struct rlimit core = {0, 0};
    setrlimit(RLIMIT_CORE, &core);
    struct rlimit cpu = {cpu_seconds, cpu_seconds};
    setrlimit(RLIMIT_CPU, &cpu);
}
