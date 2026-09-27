using CommunityToolkit.Mvvm.ComponentModel;

namespace Animosis.Client.Models;

public enum ToolState
{
    Installed,
    UpdateAvailable,
    NotInstalled,
    NotBuilt,
}

/// <summary>
/// One entry in the client's library. Mirrors a package id from the release
/// manifest (schema/manifest.schema.json) plus the presentation the shell needs.
/// </summary>
public partial class ToolItem : ObservableObject
{
    public required string Name { get; init; }
    public required string PackageId { get; init; }
    public required string Version { get; init; }
    public required string Blurb { get; init; }

    /// <summary>Two-letter plate initials.</summary>
    public required string Initials { get; init; }

    /// <summary>Set when this tool resolves to a real binary on disk.</summary>
    public string? ExecutablePath { get; set; }

    public bool CanLaunch => ExecutablePath is not null && State == ToolState.Installed;

    [ObservableProperty]
    private ToolState _state = ToolState.Installed;

    partial void OnStateChanged(ToolState value)
    {
        OnPropertyChanged(nameof(StatusText));
        OnPropertyChanged(nameof(ActionText));
        OnPropertyChanged(nameof(IsUpdateAvailable));
        OnPropertyChanged(nameof(IsInstalled));
    }

    public string StatusText => State switch
    {
        ToolState.Installed       => $"v{Version}",
        ToolState.UpdateAvailable => $"Update to {Version}",
        ToolState.NotInstalled    => "Not installed",
        ToolState.NotBuilt        => "Not built",
        _ => string.Empty,
    };

    public string ActionText => State switch
    {
        ToolState.Installed       => "Launch",
        ToolState.UpdateAvailable => "Update",
        ToolState.NotInstalled    => "Install",
        ToolState.NotBuilt        => "Build",
        _ => string.Empty,
    };

    public bool IsUpdateAvailable => State == ToolState.UpdateAvailable;
    public bool IsInstalled       => State == ToolState.Installed;

    public void Resolve(ToolState state, string? executablePath = null)
    {
        ExecutablePath = executablePath;
        State = state;
        OnPropertyChanged(nameof(CanLaunch));
    }

    /// <summary>Called when an update run completes successfully.</summary>
    public void MarkInstalled()
    {
        if (State == ToolState.UpdateAvailable)
        {
            State = ToolState.Installed;
        }
    }
}
