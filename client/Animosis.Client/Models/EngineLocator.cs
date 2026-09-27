using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Animosis.Client.Models;

public sealed record EngineBuild(string ExecutablePath, string Variant, DateTime BuiltAt, long SizeBytes)
{
    public string SizeText => $"{SizeBytes / 1024.0 / 1024.0:F1} MB";
}

/// <summary>
/// Finds a built Animosis Engine on disk.
///
/// Until the release manifest drives installs, the client discovers the engine
/// by convention. Search roots are ordered most- to least-specific; the first
/// directory that yields a binary wins.
/// </summary>
public static class EngineLocator
{
    // SCons names the binary from version.py's `short_name`, so the rebrand is
    // what makes this pattern "animosis.*" rather than "godot.*".
    private const string Pattern = "animosis.windows.editor*.exe";

    public static IEnumerable<string> SearchRoots()
    {
        // 1. Explicit override, for anyone with the engine somewhere unusual.
        var env = Environment.GetEnvironmentVariable("ANIMOSIS_ENGINE_BIN");
        if (!string.IsNullOrWhiteSpace(env))
        {
            yield return env;
        }

        // 2. Beside the client, which is where an installed build will live.
        var baseDir = AppContext.BaseDirectory;
        yield return Path.Combine(baseDir, "engine", "bin");
        yield return Path.Combine(baseDir, "engine");

        // 3. The development checkout, walking up from the client toward the
        //    repo root. Works whether the client runs from bin/Debug or dist/.
        var dir = new DirectoryInfo(baseDir);
        for (var i = 0; i < 8 && dir is not null; i++, dir = dir.Parent)
        {
            var sibling = dir.Parent is null
                ? null
                : Path.Combine(dir.Parent.FullName, "engine", "animosis-engine", "bin");

            if (sibling is not null)
            {
                yield return sibling;
            }
        }
    }

    public static EngineBuild? Find()
    {
        foreach (var root in SearchRoots())
        {
            if (string.IsNullOrWhiteSpace(root) || !Directory.Exists(root))
            {
                continue;
            }

            string[] matches;
            try
            {
                matches = Directory.GetFiles(root, Pattern);
            }
            catch (Exception)
            {
                // Unreadable directory is not an error — just not the one.
                continue;
            }

            // The console wrapper sits beside the real binary and launching it
            // opens a stray terminal, so it is filtered out rather than ranked.
            var exe = matches
                .Where(f => !Path.GetFileName(f).Contains("console", StringComparison.OrdinalIgnoreCase))
                .OrderByDescending(File.GetLastWriteTimeUtc)
                .FirstOrDefault();

            if (exe is null)
            {
                continue;
            }

            var info = new FileInfo(exe);
            return new EngineBuild(exe, DescribeVariant(info.Name), info.LastWriteTime, info.Length);
        }

        return null;
    }

    private static string DescribeVariant(string fileName)
    {
        // animosis.windows.editor.x86_64.exe -> "editor · x86_64"
        var parts = fileName.Replace(".exe", string.Empty, StringComparison.OrdinalIgnoreCase)
                            .Split('.', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length >= 4 ? $"{parts[2]} · {parts[3]}" : fileName;
    }
}
