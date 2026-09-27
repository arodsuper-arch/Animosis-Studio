using System;
using System.Diagnostics;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Animosis.Client.Models;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Animosis.Client.ViewModels;

public enum UpdatePhase
{
    Available,
    Downloading,
    Applying,
    Done,
}

public partial class MainViewModel : ViewModelBase
{
    private CancellationTokenSource? _runCts;

    // Placeholder library content so the shell can be judged. Real entries come
    // from the release manifest once Animosis.Updater is wired in.
    public ObservableCollection<ToolItem> Tools { get; } =
    [
        new ToolItem
        {
            Name = "Animosis Engine", PackageId = "animosis.engine", Version = "4.7.2",
            Initials = "AE", State = ToolState.NotBuilt,
            Blurb = "World authoring, scene graph and the play-in-editor runtime. Forked from Godot 4.7.2-stable.",
        },
        new ToolItem
        {
            Name = "Character Creator", PackageId = "animosis.character", Version = "0.5.0",
            Initials = "CC", State = ToolState.UpdateAvailable,
            Blurb = "Rigging, morph targets and scalable body and face parameter sets.",
        },
        new ToolItem
        {
            Name = "Terrain Forge", PackageId = "animosis.terrain", Version = "0.5.0",
            Initials = "TF", State = ToolState.UpdateAvailable,
            Blurb = "Procedural generation, streaming chunks and LOD authoring.",
        },
        new ToolItem
        {
            Name = "Asset Designer", PackageId = "animosis.assets", Version = "0.5.0",
            Initials = "AD", State = ToolState.Installed,
            Blurb = "Material graphs, mesh import and the shared asset pipeline.",
        },
        new ToolItem
        {
            Name = "Motion Studio", PackageId = "animosis.motion", Version = "0.5.0",
            Initials = "MS", State = ToolState.NotInstalled,
            Blurb = "Animation graphs, locomotion state machines and effects.",
        },
        new ToolItem
        {
            Name = "Systems Bench", PackageId = "animosis.systems", Version = "0.5.0",
            Initials = "SB", State = ToolState.NotInstalled,
            Blurb = "Headless harness for combat, economy and progression rules.",
        },
    ];

    public ObservableCollection<string> Log { get; } =
    [
        "manifest.json fetched — 4.2 kB",
        "signature verified — ed25519 key 2026a",
        "serial 42 accepted (last seen 41)",
        "plan: 2 deltas, 1 full — 377.5 MB",
    ];

    // ---- Navigation --------------------------------------------------------

    public MainViewModel()
    {
        RefreshEngine();
    }

    [ObservableProperty]
    private string _enginePath = "not found";

    // Remembers the last resolution so repeated rescans stay silent. The window
    // rescans every time it is activated, so logging unconditionally would bury
    // the update log in noise.
    private string? _lastResolved;

    /// <summary>
    /// Resolves the Animosis Engine entry against a real binary on disk. Until
    /// the release manifest drives installs, the client discovers the engine by
    /// convention; see EngineLocator.
    /// </summary>
    [RelayCommand]
    private void RefreshEngine()
    {
        var engine = Tools.FirstOrDefault(t => t.PackageId == "animosis.engine");
        if (engine is null)
        {
            return;
        }

        var build = EngineLocator.Find();

        if (build is null)
        {
            engine.Resolve(ToolState.NotBuilt);
            EnginePath = "not found — build it in engine/animosis-engine";
            if (_lastResolved is not null)
            {
                Log.Add("engine: build disappeared from all search roots");
                _lastResolved = null;
            }

            return;
        }

        engine.Resolve(ToolState.Installed, build.ExecutablePath);
        EnginePath = build.ExecutablePath;

        var stamp = $"{build.ExecutablePath}|{build.BuiltAt:O}";
        if (_lastResolved != stamp)
        {
            Log.Add($"engine: {build.Variant}, {build.SizeText}, built {build.BuiltAt:yyyy-MM-dd HH:mm}");
            _lastResolved = stamp;
        }
    }

    [ObservableProperty]
    private int _selectedPage;

    partial void OnSelectedPageChanged(int value)
    {
        OnPropertyChanged(nameof(IsLibrary));
        OnPropertyChanged(nameof(IsUpdates));
        OnPropertyChanged(nameof(IsSettings));
        OnPropertyChanged(nameof(PageTitle));
        OnPropertyChanged(nameof(PageSubtitle));
        OnPropertyChanged(nameof(LibraryOpacity));
        OnPropertyChanged(nameof(UpdatesOpacity));
        OnPropertyChanged(nameof(SettingsOpacity));
        OnPropertyChanged(nameof(LibraryBar));
        OnPropertyChanged(nameof(UpdatesBar));
        OnPropertyChanged(nameof(SettingsBar));
    }

    [RelayCommand]
    private void SelectPage(string index) => SelectedPage = int.Parse(index);

    public bool IsLibrary  => SelectedPage == 0;
    public bool IsUpdates  => SelectedPage == 1;
    public bool IsSettings => SelectedPage == 2;

    // Selection is expressed as opacity so the nav needs no value converters.
    public double LibraryOpacity  => IsLibrary  ? 1.0 : 0.5;
    public double UpdatesOpacity  => IsUpdates  ? 1.0 : 0.5;
    public double SettingsOpacity => IsSettings ? 1.0 : 0.5;
    public double LibraryBar      => IsLibrary  ? 1.0 : 0.0;
    public double UpdatesBar      => IsUpdates  ? 1.0 : 0.0;
    public double SettingsBar     => IsSettings ? 1.0 : 0.0;

    public string PageTitle => SelectedPage switch
    {
        0 => "Library", 1 => "Updates", 2 => "Settings", _ => string.Empty,
    };

    public string PageSubtitle => SelectedPage switch
    {
        0 => "Tools installed on this machine.",
        1 => "Channel: stable",
        2 => "Install location, channel and startup behaviour.",
        _ => string.Empty,
    };

    public string ClientVersion => "v0.3.0";
    public string InstallPath   => @"C:\Program Files\Animosis Studio";

    // ---- Update run --------------------------------------------------------

    [ObservableProperty]
    private UpdatePhase _phase = UpdatePhase.Available;

    partial void OnPhaseChanged(UpdatePhase value)
    {
        OnPropertyChanged(nameof(UpdateHeadline));
        OnPropertyChanged(nameof(UpdateSubline));
        OnPropertyChanged(nameof(CanInstall));
        OnPropertyChanged(nameof(CanCancel));
        OnPropertyChanged(nameof(IsFinished));
        OnPropertyChanged(nameof(ShowProgress));
        OnPropertyChanged(nameof(IsIndeterminate));
    }

    [ObservableProperty]
    private double _progressPercent;

    [ObservableProperty]
    private string _progressDetail = "3 packages to update";

    [ObservableProperty]
    private string _progressNumbers = "377.5 MB";

    public bool CanInstall      => Phase == UpdatePhase.Available;
    public bool CanCancel       => Phase == UpdatePhase.Downloading;
    public bool IsFinished      => Phase == UpdatePhase.Done;
    public bool ShowProgress    => Phase is UpdatePhase.Downloading or UpdatePhase.Applying;
    public bool IsIndeterminate => Phase == UpdatePhase.Applying;

    public string UpdateHeadline => Phase switch
    {
        UpdatePhase.Available   => "Update available — 0.5.0",
        UpdatePhase.Downloading => "Updating to 0.5.0",
        UpdatePhase.Applying    => "Applying update",
        UpdatePhase.Done        => "Updated to 0.5.0",
        _ => string.Empty,
    };

    public string UpdateSubline => Phase switch
    {
        UpdatePhase.Available   => "You are on 0.4.1. Nothing changes on disk until every file is downloaded and verified.",
        UpdatePhase.Downloading => "Downloading and verifying. You can cancel safely — your install is untouched.",
        UpdatePhase.Applying    => "Swapping files in. This is quick — please do not close the client.",
        UpdatePhase.Done        => "All packages verified and installed.",
        _ => string.Empty,
    };

    public string SignatureText => "Signature verified · serial 42";

    /// <summary>
    /// Stand-in for the real run. It drives the exact phases and bindings that
    /// Animosis.Updater will report, so swapping the real engine in changes no
    /// XAML — only where these values come from.
    /// </summary>
    [RelayCommand]
    private async Task InstallAsync()
    {
        _runCts?.Cancel();
        _runCts = new CancellationTokenSource();
        var token = _runCts.Token;

        Phase = UpdatePhase.Downloading;
        ProgressPercent = 0;
        Log.Add("staging/ prepared");

        const double totalMb = 377.5;
        var marks = new[] { (18.0, "animosis.schema patched — sha256 ok"),
                            (48.0, "animosis.core patched — sha256 ok"),
                            (96.0, "animosis.terrain fetched — sha256 ok") };
        var nextMark = 0;

        try
        {
            while (ProgressPercent < 100)
            {
                await Task.Delay(90, token);
                ProgressPercent = Math.Min(100, ProgressPercent + 2.4);

                var doneMb = totalMb * ProgressPercent / 100.0;
                ProgressDetail = $"Downloading — {(nextMark < marks.Length ? marks[nextMark].Item2.Split(' ')[0] : "animosis.terrain")}";
                ProgressNumbers = $"{doneMb:F1} / {totalMb:F1} MB";

                if (nextMark < marks.Length && ProgressPercent >= marks[nextMark].Item1)
                {
                    Log.Add(marks[nextMark].Item2);
                    nextMark++;
                }
            }

            Phase = UpdatePhase.Applying;
            ProgressDetail = "Writing journal…";
            Log.Add("journal written, fsync ok");
            await Task.Delay(700, token);

            ProgressDetail = "Swapping files…";
            Log.Add("3 packages staged → live");
            await Task.Delay(800, token);

            Log.Add("state.json committed");
            Log.Add("journal cleared, backup removed");
            Phase = UpdatePhase.Done;
            ProgressDetail = "3 packages updated and verified";
            ProgressNumbers = string.Empty;

            foreach (var t in Tools)
            {
                t.MarkInstalled();
            }
            OnPropertyChanged(nameof(Tools));
        }
        catch (OperationCanceledException)
        {
            Phase = UpdatePhase.Available;
            ProgressPercent = 0;
            ProgressDetail = "3 packages to update";
            ProgressNumbers = "377.5 MB";
            Log.Add("cancelled — install untouched, staging discarded");
        }
    }

    [RelayCommand]
    private void Cancel() => _runCts?.Cancel();

    [RelayCommand]
    private void Recheck()
    {
        _runCts?.Cancel();
        Phase = UpdatePhase.Available;
        ProgressPercent = 0;
        ProgressDetail = "3 packages to update";
        ProgressNumbers = "377.5 MB";
        Log.Add("re-checking stable channel…");
    }

    // ---- Library actions ---------------------------------------------------

    [RelayCommand]
    private void ToolAction(ToolItem? tool)
    {
        if (tool is null)
        {
            return;
        }

        if (tool.State == ToolState.Installed)
        {
            if (tool.ExecutablePath is null)
            {
                Log.Add($"launch requested — {tool.PackageId} v{tool.Version} (no binary bound)");
                return;
            }

            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = tool.ExecutablePath,
                    WorkingDirectory = Path.GetDirectoryName(tool.ExecutablePath),
                    UseShellExecute = true,
                });
                Log.Add($"launched {tool.PackageId} — {Path.GetFileName(tool.ExecutablePath)}");
            }
            catch (Exception ex)
            {
                // Surfaced rather than swallowed: a failed launch is the single
                // most common thing a user will report.
                Log.Add($"launch FAILED — {tool.PackageId}: {ex.Message}");
                SelectedPage = 1;
            }

            return;
        }

        if (tool.State == ToolState.NotBuilt)
        {
            Log.Add($"{tool.PackageId} is not built — compile it, then press Rescan on Settings");
            SelectedPage = 2;
            return;
        }

        // Update and Install both belong on the Updates page, which is where the
        // plan, the size and the signature actually live.
        Log.Add($"{(tool.State == ToolState.UpdateAvailable ? "update" : "install")} queued — {tool.PackageId}");
        SelectedPage = 1;
    }
}
