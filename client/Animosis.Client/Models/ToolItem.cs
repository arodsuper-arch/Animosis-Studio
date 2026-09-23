using CommunityToolkit.Mvvm.ComponentModel;

namespace Animosis.Client.Models;

public enum ToolState
{
    Installed,
    UpdateAvailable,
    NotInstalled,
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
        _ => string.Empty,
    };

    public string ActionText => State switch
    {
        ToolState.Installed       => "Launch",
        ToolState.UpdateAvailable => "Update",
        ToolState.NotInstalled    => "Install",
        _ => string.Empty,
    };

    public bool IsUpdateAvailable => State == ToolState.UpdateAvailable;
    public bool IsInstalled       => State == ToolState.Installed;

    /// <summary>Called when an update run completes successfully.</summary>
    public void MarkInstalled()
    {
        if (State == ToolState.UpdateAvailable)
        {
            State = ToolState.Installed;
        }
    }
}
