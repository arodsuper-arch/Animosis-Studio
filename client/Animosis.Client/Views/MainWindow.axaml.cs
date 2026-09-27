using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;

namespace Animosis.Client.Views;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
    }

    // The window is frameless (SystemDecorations="None") so the custom title bar
    // has to carry the drag itself.
    private void TitleBar_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
        {
            BeginMoveDrag(e);
        }
    }

    // Rescan whenever the window comes forward. Building the engine happens in a
    // terminal; alt-tabbing back should be enough to pick it up, without the
    // user knowing a Rescan button exists.
    private void Window_Activated(object? sender, System.EventArgs e)
    {
        if (DataContext is ViewModels.MainViewModel vm && vm.RefreshEngineCommand.CanExecute(null))
        {
            vm.RefreshEngineCommand.Execute(null);
        }
    }

    private void Minimize_Click(object? sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;

    private void Close_Click(object? sender, RoutedEventArgs e) => Close();
}
