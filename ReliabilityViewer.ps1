If ($PSVersionTable.PSVersion.Major -lt 3)
{
    $msg = New-Object -ComObject Wscript.Shell
    $msg.popup("Your PowerShell version is $($PSVersionTable.PSVersion).  A minimum of PowerShell 3.0 is required.",0,'PowerShell 3.0 required',0 + 16)
    continue
}

If (Test-Path "$env:ProgramFiles\SMSAgent\Reliability Viewer for Windows")
{
    $Source = "$env:ProgramFiles\SMSAgent\Reliability Viewer for Windows"
}
If (Test-Path "${env:ProgramFiles(x86)}\SMSAgent\Reliability Viewer for Windows")
{
    $Source = "${env:ProgramFiles(x86)}\SMSAgent\Reliability Viewer for Windows"
}

# Load the WPF assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -Path "$Source\bin\MaterialDesignColors.dll"
Add-Type -Path "$Source\bin\MaterialDesignThemes.Wpf.dll"


#region GUI
# Main app window
[XML]$Xaml = [System.IO.File]::ReadAllLines("$Source\XAML Files\App.xaml") 

# Summary data window
[XML]$Xaml2 = [System.IO.File]::ReadAllLines("$Source\XAML Files\Summary.xaml") 

# About window
[XML]$Xaml3 = [System.IO.File]::ReadAllLines("$Source\XAML Files\About.xaml") 

$script:hash = [hashtable]::Synchronized(@{})
$hash.Window = [Windows.Markup.XamlReader]::Load((New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $xaml))
$hash.Host = $host
$xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
    $hash.$($_.Name) = $hash.Window.FindName($_.Name)
}

# Set some initial values
$hash.ComputerName.Text = $env:COMPUTERNAME
if (Test-Path -Path "$env:ProgramFiles\SMSAgent\Reliability Viewer for Windows\bin\Gear.ico")
{
    $hash.Window.Icon = "$env:ProgramFiles\SMSAgent\Reliability Viewer for Windows\bin\Gear.ico"
}
if (Test-Path -Path "${env:ProgramFiles(x86)}\SMSAgent\Reliability Viewer for Windows\bin\Gear.ico")
{
    $hash.Window.Icon = "${env:ProgramFiles(x86)}\SMSAgent\Reliability Viewer for Windows\bin\Gear.ico"
}

#endregion


# Load in some functions
. "$Source\bin\FunctionLibrary.ps1"



#region Events
$hash.GetRecords.Add_Click({
        $hash.DataGrid.ItemsSource = ''
        $hash.Message.Text = "Retrieving records from $($hash.Computername.Text).  Please wait..."
        Get-ReliablityRecords
})

$hash.ComputerName.Add_KeyDown({
        if ($_.Key -eq 'Return')
        {
            $hash.DataGrid.ItemsSource = ''
            $hash.Message.Text = "Retrieving records from $($hash.Computername.Text).  Please wait..."
            Get-ReliablityRecords
        }
})

$hash.ProductName.Add_SelectionChanged({
        Apply-Filter
})
$hash.Source.Add_SelectionChanged({
        Apply-Filter
})

$hash.EventID.Add_SelectionChanged({
        Apply-Filter
})

$hash.Log.Add_SelectionChanged({
        Apply-Filter
})

$hash.User.Add_SelectionChanged({
        Apply-Filter
})
$hash.ClearFilter.Add_Click({
        $hash.ProductName.SelectedValue = '*'
        $hash.Source.SelectedValue = '*'
        $hash.EventID.SelectedValue = '*'
        $hash.Log.SelectedValue = '*'
        $hash.User.SelectedValue = '*'
        $hash.DataGrid.ItemsSource = [array]$hash.Records
})

$hash.Datagrid.Add_SelectionChanged({
        Populate-Message
})

$hash.SummaryButton.Add_Click({
        if ($hash.Records -ne '' -and $hash.Records -ne $null)
        {
            Display-SummaryData
        }
})

$hash.ChartButton.Add_Click({
        $msg = New-Object -ComObject Wscript.Shell
        if (($msg.popup('This action will generate a chart from the reliability metrics of the target machine in a Microsoft Excel workbook.  Do you wish to continue?',0,'Generate System Stability Chart',4 + 32)) -eq 7)
        {
            continue
        }
        else 
        {
            Get-ReliabilityMetricsAsChart
        }
})

$hash.AboutButton.Add_Click({
        Display-About
})
#endregion


# If code is running in ISE, use ShowDialog()...
if ($psISE)
{
    $null = $Hash.window.Dispatcher.InvokeAsync{$Hash.window.ShowDialog()}.Wait()
}
# ...otherwise run as an application
Else
{
    # Make PowerShell Disappear
    $windowcode = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
    $asyncwindow = Add-Type -MemberDefinition $windowcode -Name Win32ShowWindowAsync -Namespace Win32Functions -PassThru
    $null = $asyncwindow::ShowWindowAsync((Get-Process -PID $pid).MainWindowHandle, 0)
 
    $app = New-Object -TypeName Windows.Application
    $app.Run($Hash.Window)
}