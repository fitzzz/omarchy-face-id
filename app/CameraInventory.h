// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QString>

class DiagnosticLog;

class CameraInventory final
{
public:
    static void recordSnapshot(DiagnosticLog &log,
                               const QString &gazeConfigPath,
                               const QString &trigger);
};
