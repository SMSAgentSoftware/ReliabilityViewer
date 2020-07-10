function script:Start-RSJob
{
    param(
        [parameter(Mandatory = $True,Position = 0)]
        [ScriptBlock]$Code,
        [parameter()]
        $Arguments
    )
    $Runspace = [runspacefactory]::CreateRunspace()
    $PowerShell = [powershell]::Create()
    $PowerShell.runspace = $Runspace
    $Runspace.Open()
    [void]$PowerShell.AddScript($Code)
    foreach ($Argument in $Arguments)
    {
        [void]$PowerShell.AddArgument($Argument)
    }
    $job = $PowerShell.BeginInvoke()
    #$result = $Powershell.EndInvoke($job)
    #$result
}

function Get-ReliablityRecords 
{
    # Define code to run
    $Code = 
    {
        param($hash,$Computername)
        
        # Retrieve reliability records from WMI
        $Script = {
            Get-WmiObject -Class win32_ReliabilityRecords
        }
        if ($Computername -eq $env:COMPUTERNAME)
        {
            $Records = Invoke-Command -ScriptBlock $Script
        }
        Else 
        {
            if (Test-Connection -ComputerName $Computername -Count 2 -Quiet)
            {
                try
                {
                    $Records = Invoke-Command -ComputerName $Computername -ScriptBlock $Script -ErrorAction Stop
                }
                # Prompt for credentials if access is denied, else return the error
                catch
                {
                    if ($Error[0] | Select-String -Pattern 'Access is denied')
                    {
                        $Credentials = $hash.host.ui.PromptForCredential('Credentials required', "Access was denied to $Computername.  Enter credentials to connect.", '', '')
                        $hash.Credentials = $Credentials
                        try
                        {
                            $Records = Invoke-Command -ComputerName $Computername -ScriptBlock $Script -Credential $Credentials -ErrorAction Stop
                        }
                        Catch
                        {
                            $myerror = $($Error[0].Exception.Message)
                            $hash.Window.Dispatcher.Invoke(
                                [action]{
                                    $hash.Message.Text = "[ERROR!] $myerror "
                            })
                            continue
                        }
                    }
                    Else
                    {
                        $myerror = $($Error[0].Exception.Message)
                        $hash.Window.Dispatcher.Invoke(
                            [action]{
                                $hash.Message.Text = "[ERROR!] $myerror"
                        })
                        continue
                    }
                }
            }
            Else 
            {
                $hash.Window.Dispatcher.Invoke(
                    [action]{
                        $hash.Message.Text = "[ERROR!] $Computername could not be contacted."
                })
                continue
            }
        }

        # If no data
        if ($Records -eq '' -or $Records -eq $null)
        {
            $hash.Window.Dispatcher.Invoke(
                [action]{
                    $hash.Message.Text = "No reliability data found for $Computername"
            })
            continue
        }

        # Filter just the info we want and add to synchronised hash table
        $hash.Records = $Records |
        Select-Object -Property TimeGenerated, SourceName, User, LogFile, ProductName, EventIdentifier, Message, RecordNumber |
        ForEach-Object -Process {
            New-Object -TypeName psobject -Property @{
                TimeGenerated = [System.Management.ManagementDateTimeconverter]::ToDateTime($_.TimeGenerated) |
                Get-Date -Format 'dd-MMM-yyyy hh:mm:ss'
                Source        = $_.SourceName
                User          = $_.User
                LogFile       = $_.LogFile
                ProductName   = $_.ProductName
                EventID       = $_.EventIdentifier
                Message       = $_.Message
                RecordNumber  = $_.RecordNumber
            }
        }

        # Set the values for the filter combo boxes
        [array]$Source = $hash.Records | Select-Object -ExpandProperty Source -Unique
        $Source += '*' 
        $Source = $Source | Sort-Object
        [array]$ProductName = $hash.Records | Select-Object -ExpandProperty ProductName -Unique
        $ProductName += '*'
        $ProductName = $ProductName | Sort-Object
        [array]$EventID = $hash.Records | Select-Object -ExpandProperty EventID -Unique
        $EventID += '*'
        $EventID = $EventID | Sort-Object
        [array]$Log = $hash.Records | Select-Object -ExpandProperty LogFile -Unique
        $Log += '*'
        $Log = $Log | Sort-Object
        [array]$User = $hash.Records | Select-Object -ExpandProperty User -Unique
        $User += '*'
        $User = $User | Sort-Object

        # Update the GUI
        $hash.Window.Dispatcher.Invoke(
            [action]{
                $hash.Message.Text = ''
                $hash.Source.ItemsSource = $Source
                $hash.Source.SelectedValue = '*'
                $hash.ProductName.ItemsSource = $ProductName
                $hash.ProductName.SelectedValue = '*'
                $hash.EventID.ItemsSource = $EventID
                $hash.EventID.SelectedValue = '*'
                $hash.Log.ItemsSource = $Log
                $hash.Log.SelectedValue = '*'
                $hash.User.ItemsSource = $User
                $hash.User.SelectedValue = '*'
                $hash.DataGrid.ItemsSource = [array]$hash.Records
        })
    }
    
    # Define variables to use
    $Computername = $hash.ComputerName.Text

    # Run code in seperate runspace
    Start-RSJob -Code $Code -Arguments $hash, $Computername
}

function Populate-Message 
{
    # Get record number of selected grid item
    $Record = $hash.DataGrid.SelectedItem.RecordNumber

    # Filter the records to find that one
    $msg = $hash.Records |
    Select-Object -Property * |
    Where-Object -FilterScript {
        $_.RecordNumber -eq $Record
    }

    # Display the message in the message box
    $hash.Message.Text = $msg.Message
}

Function Apply-Filter
{
    # Put the currently selected filter items into variables
    $ProductName = $hash.ProductName.SelectedItem
    $Source = $hash.Source.SelectedItem
    $EventID = $hash.EventID.SelectedItem
    $Log = $hash.Log.SelectedItem
    $User = $hash.User.SelectedItem

    # Search the records with the filter
    $FilterResults = $hash.Records | 
    Where-Object -FilterScript {
        $_.ProductName -like $ProductName -and $_.Source -like $Source -and $_.EventID -like $EventID -and $_.LogFile -like $Log -and $_.User -like $User
    }

    # Display the filtered results in the grid
    $hash.DataGrid.ItemsSource = [array]$FilterResults
}

function Display-SummaryData
{
    $hash.Window2 = [Windows.Markup.XamlReader]::Load((New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $xaml2))
    $xaml2.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
        $hash.$($_.Name) = $hash.Window2.FindName($_.Name)
    }
    $hash.Window2.Title = "Reliability Record Summary Data for $($hash.ComputerName.Text)"
    [array]$hash.SummaryProduct.ItemsSource = $hash.Records |
    Group-Object -Property ProductName -NoElement |
    Select-Object -Property Count, @{
        l = 'Product'
        e = {
            $_.Name
        }
    } |
    Sort-Object -Property count -Descending
    [array]$hash.SummarySource.ItemsSource = $hash.Records |
    Group-Object -Property Source -NoElement |
    Select-Object -Property Count, @{
        l = 'Source'
        e = {
            $_.Name
        }
    } |
    Sort-Object -Property count -Descending
    [array]$hash.SummaryEventID.ItemsSource = $hash.Records |
    Group-Object -Property EventID -NoElement |
    Select-Object -Property Count, @{
        l = 'EventID'
        e = {
            $_.Name
        }
    } |
    Sort-Object -Property count -Descending
    [array]$hash.SummaryUser.ItemsSource = $hash.Records |
    Group-Object -Property User -NoElement |
    Select-Object -Property Count, @{
        l = 'User'
        e = {
            $_.Name
        }
    } |
    Sort-Object -Property count -Descending
    [array]$hash.SummaryLog.ItemsSource = $hash.Records |
    Group-Object -Property LogFile -NoElement |
    Select-Object -Property Count, @{
        l = 'Log'
        e = {
            $_.Name
        }
    } |
    Sort-Object -Property count -Descending

    $hash.Window2.Add_MouseUp({
            $hash.Window2.Close()
    })

    $null = $hash.Window2.ShowDialog()
}

function Display-About
{
    $hash.Window3 = [Windows.Markup.XamlReader]::Load((New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $xaml3))
    $xaml3.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
        $hash.$($_.Name) = $hash.Window3.FindName($_.Name)
    }

    $hash.Link1.Add_Click({
            Start-Process -FilePath 'http://smsagent.wordpress.com/tools/reliability-viewer-for-windows/'
    })

    $null = $hash.Window3.ShowDialog()
}

function Get-ReliabilityMetricsAsChart
{
    $Code = {
        param($hash,$Computername)      
        
        if (Test-Connection -ComputerName $Computername -Count 2 -Quiet)
        {
            # Retrieve reliability metrics data and put into a psobject
            If ($Computername -eq $env:COMPUTERNAME)
            {
                $RelStabilityMetrics = Get-WmiObject -Class win32_ReliabilityStabilityMetrics |
                Select-Object -Property TimeGenerated, SystemStabilityIndex |
                ForEach-Object -Process {
                    $properties = [ordered]@{
                        TimeGenerated        = [System.Management.ManagementDateTimeconverter]::ToDateTime($_.TimeGenerated)
                        SystemStabilityIndex = ([double]$_.SystemStabilityIndex -join '.')
                    }
                    New-Object -TypeName psobject -Property $properties
                }
            }
            Else 
            {
                try
                {
                    $RelStabilityMetrics = Invoke-Command -ComputerName $Computername -ScriptBlock {
                        Get-WmiObject -Class win32_ReliabilityStabilityMetrics
                    } -ErrorAction Stop |
                    Select-Object -Property TimeGenerated, SystemStabilityIndex |
                    ForEach-Object -Process {
                        $properties = [ordered]@{
                            TimeGenerated        = [System.Management.ManagementDateTimeconverter]::ToDateTime($_.TimeGenerated)
                            SystemStabilityIndex = ([double]$_.SystemStabilityIndex -join '.')
                        }
                        New-Object -TypeName psobject -Property $properties
                    }
                }
                # Prompt for credentials if access is denied, else return the error
                catch
                {
                    if ($Error[0] | Select-String -Pattern 'Access is denied')
                    {
                        if ($hash.Credentials)
                        {
                            $RelStabilityMetrics = Invoke-Command -ComputerName $Computername -ScriptBlock {
                                Get-WmiObject -Class win32_ReliabilityStabilityMetrics
                            } -Credential $hash.Credentials |
                            Select-Object -Property TimeGenerated, SystemStabilityIndex |
                            ForEach-Object -Process {
                                $properties = [ordered]@{
                                    TimeGenerated        = [System.Management.ManagementDateTimeconverter]::ToDateTime($_.TimeGenerated)
                                    SystemStabilityIndex = ([double]$_.SystemStabilityIndex -join '.')
                                }
                                New-Object -TypeName psobject -Property $properties
                            }
                        }
                        Else
                        {
                            $Credentials = $hash.host.ui.PromptForCredential('Credentials', "Access was denied to $Computername.  Enter credentials to connect.", '', '')
                            try
                            {
                                $RelStabilityMetrics = Invoke-Command -ComputerName $Computername -ScriptBlock {
                                    Get-WmiObject -Class win32_ReliabilityStabilityMetrics
                                } -Credential $Credentials -ErrorAction Stop |
                                Select-Object -Property TimeGenerated, SystemStabilityIndex |
                                ForEach-Object -Process {
                                    $properties = [ordered]@{
                                        TimeGenerated        = [System.Management.ManagementDateTimeconverter]::ToDateTime($_.TimeGenerated)
                                        SystemStabilityIndex = ([double]$_.SystemStabilityIndex -join '.')
                                    }
                                    New-Object -TypeName psobject -Property $properties
                                }
                            }
                            Catch
                            {
                                $myerror = $($Error[0].Exception.Message)
                                $hash.Window.Dispatcher.Invoke(
                                    [action]{
                                        $hash.Message.Text = "[ERROR!] $myerror"
                                })
                                continue
                            }
                        }
                        Else
                        {
                            $myerror = $($Error[0].Exception.Message)
                            $hash.Window.Dispatcher.Invoke(
                                [action]{
                                    $hash.Message.Text = "[ERROR!] $myerror"
                            })
                            continue
                        }
                    }
                }
            }
            # If no data found
            if ($RelStabilityMetrics -eq '' -or $RelStabilityMetrics -eq $null)
            {
                $myerror = Write-Warning -Message "No reliability metric data found for $Computername"
                $hash.Window.Dispatcher.Invoke(
                    [action]{
                        $hash.Message.Text = $myerror
                })
                continue
            }

            # Export data into CSV
            $SourceFile = "$env:temp\ReliabilityMetrics-$Computername.csv"
            $RelStabilityMetrics |
            Where-Object -FilterScript {
                $_.TimeGenerated -match '00:00:00'
            } |
            Export-Csv -Path $SourceFile -NoTypeInformation

            # Create the Excel object
            try 
            {
                $Excel = [System.Runtime.InteropServices.Marshal]::GetActiveObject('Excel.Application')
            }
            catch [System.Management.Automation.MethodInvocationException] 
            {
                try 
                {
                    $Excel = New-Object -ComObject 'Excel.Application'
                }
                catch 
                {
                    $myerror = Write-Error -Message 'Could not create Excel object.  Check that Microsoft Excel is installed.'
                    $hash.Window.Dispatcher.Invoke(
                        [action]{
                            $hash.Message.Text = $myerror
                    })
                    continue
                }
            }
            [System.Globalization.CultureInfo]$tempculture = 'en-GB'
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $tempculture 

            $Excel.Visible = $false
            $Excel.DisplayAlerts = $false

            # Add a workbook and copy CSV into it
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $tempculture 
            $TargetWorkBook = $Excel.Workbooks.Add()
            $TargetSheet = $TargetWorkBook.Worksheets.Item(1)
            $SourceWorkbook = $Excel.Workbooks.Open($SourceFile)
            $sourceSheet = $SourceWorkbook.Worksheets.Item(1)
            $sourceSheet.Copy($TargetSheet)

            # Add a chart in the workbook
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $tempculture 
            $TargetSheet = $TargetWorkBook.Worksheets.Item(1)
            Add-Type -AssemblyName Microsoft.Office.Interop.Excel
            $xlDirection = [Microsoft.Office.Interop.Excel.XLDirection]
            $Chart = $TargetWorkBook.Charts.Add()
            $Chart.ChartType = 4
            try 
            {
                $Chart.ChartStyle = 227
            }
            catch 
            {

            }
            $Chart.HasTitle = $True
            $Chart.ChartTitle.Text = "System Reliability Metrics for $Computername"
            $Chart.Name = 'Reliability Metrics Chart'

            # Define and set range for chart source data
            try 
            {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $tempculture 
                $start = $TargetSheet.range('A2')
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $tempculture 
                $X = $TargetSheet.Range($start,$start.End($xlDirection::xlDown))
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $tempculture 
                $start = $TargetSheet.range('B2')
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $tempculture 
                $Y = $TargetSheet.Range($start,$start.End($xlDirection::xlDown))
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $tempculture 
                $chartdata = $TargetSheet.Range("A$($Y.item(1).Row):A$($Y.item($Y.count).Row),B$($X.item(1).Row):B$($X.item($X.count).Row)")
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $tempculture 
                $Chart.SetSourceData($chartdata)
            }
            catch 
            {

            }
            $Chart.SeriesCollection(1).Name = 'System Reliability Metrics'
            $Chart.Axes(2).MaximumScaleIsAuto = $false
            $Chart.Axes(2).MaximumScale = 10
            $Chart.Axes(2).MinimumScaleIsAuto = $false
            $Chart.Axes(2).MinimumScale = 0

            # Close CSV and delete additional sheet from workbook
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $tempculture 
            $SourceWorkbook.Close()
             
            try 
            {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $tempculture
                $TargetWorkBook.Worksheets.Item('Sheet1').Delete()
            }
            catch 
            {

            }
            try 
            {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $tempculture
                $TargetWorkBook.Worksheets.Item('Sheet2').Delete()
            }
            catch 
            {

            }
            try 
            {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $tempculture
                $TargetWorkBook.Worksheets.Item('Sheet3').Delete()
            }
            catch 
            {

            }

            # Delete CSV
            Remove-Item $SourceFile -Force

            # Make Excel visible and release the com object
            $Excel.Visible = $True
            $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject([System.__ComObject]$Excel)
        }
        Else
        {
            $hash.Window.Dispatcher.Invoke(
                [action]{
                    $hash.Message.Text = "[ERROR!] $Computername could not be contacted."
            })
            continue
        }
    }

    # Define variables to use
    $Computername = $hash.ComputerName.Text

    # Run code in seperate runspace
    Start-RSJob -Code $Code -Arguments $hash, $Computername
}