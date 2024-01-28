Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Global Variables
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$profilesPath = Join-Path -Path $scriptPath -ChildPath 'IPGUI Profiles'

# Ensure Directory for Profiles Exists
If (!(Test-Path $profilesPath)) {
    New-Item -ItemType 'Directory' -Path $profilesPath
}

# Function to Enumerate Network Adapters
Function Get-NetworkAdapters {
    Get-NetAdapter | Select-Object Name, InterfaceDescription, ifIndex, InterfaceGuid
}

# Function to Set Global Network Variables Based on Selected Adapter
Function Set-NetworkAdapter($adapterName) {
    Try {
        $global:network = Get-NetAdapter | Where-Object {$_.Name -eq $adapterName}
        $global:ifGuid = $network.InterfaceGuid
        $null = Set-NetIPInterface -ErrorAction Stop -InterfaceAlias $network.ifAlias -Dhcp Disabled
    } Catch {
        $outputContentLabel.ForeColor = '0xaa0000'
        $outputContentLabel.Text = "Error: $($Error[0])"
    }
}

Function Get-EthAdaptorIPAddress {
    $currentIPInfo = Get-NetIPAddress -InterfaceIndex $network.ifIndex | Where {$null -ne $_.IPv4Address}
    $currentIPAddress = $currentIPInfo.IPAddress
    $currentSubnetPrefix = $currentIPInfo.PrefixLength
    $currentGateway = (Get-NetRoute | Where-Object {$_.DestinationPrefix -eq '0.0.0.0/0' -and $_.InterfaceAlias -eq $network.InterfaceAlias}).NextHop
    $profileHash = @{
        Gateway = $currentGateway
        SubnetMask = $currentSubnetPrefix
        IPAddress = $currentIPAddress
    }
    $profile = New-Object -TypeName PSObject -Property $profileHash
    Return $profile
}

Function Get-SubnetPrefix {
    Param()
    $subnetPrefix = $subnetTextbox.Text.Replace('/','')
    If ($subnetPrefix.contains('.')) {
        $subnetPrefix = Convert-IpAddressToMaskLength -dottedIpAddressString $subnetPrefix
    }
    Return $subnetPrefix
}

Function Get-IPProfiles {
    Param()
    $profiles = @()
    $profileFiles = Get-ChildItem -Path $profilesPath -File
    Foreach ($profile in $profileFiles) {
        $profiles += $profile.BaseName
    }
    Return @('Current IP Settings', 'DHCP (Default Settings)') + $profiles
}

Function Get-IPProfile {
    Param($name)
    #set output to "Getting profile $name from $profilesPath"
    If ($name -eq 'Current IP Settings') {
        $profile = Get-EthAdaptorIPAddress
    } ElseIf ($name -eq 'DHCP (Default Settings)') {
        New-IPProfile
    } Else {
        $text = (Get-Content -Path "$profilesPath\$name.txt" -Raw).Replace(':','=')
        $hereText = @"
$text
"@
        $profile = ConvertFrom-StringData $hereText
    }
    $profileNameTextbox.Text = $name
    $gatewayTextbox.Text = "$($profile.Gateway)"
    $subnetTextbox.Text = "$($profile.SubnetMask)"
    $ipAddressTextbox.Text = "$($profile.IPAddress)"
    #set output to "Completed Action"?
}

Function New-IPProfile {
    Param()
    $profileNameTextbox.Text = ""
    $gatewayTextbox.Text = ""
    $subnetTextbox.Text = ""
    $ipAddressTextbox.Text = ""
}

Function Save-IPProfile {
    Param()
    $errorSaving = $False
    $outputContentLabel.ForeColor = '0xFD7F20'
    $outputContentLabel.Text = "Saving profile $($profileNameTextbox.Text)"
    #set defaults if any blank and reload profile ready for apply in case run after
    If ($subnetTextbox.Text -eq "") {
        $errorSaving = $True
        $errorMessage = "No subnet address provided."
    }
    If ($ipAddressTextbox.Text -eq "") {
        $errorSaving = $True
        $errorMessage = "No IP address provided."
    }
    If ($profileNameTextbox.Text -eq "") {
        $errorSaving = $True
        $errorMessage = "Profile has no name."
    }
    If ($profileDropdown.SelectedItem -in @('DHCP (Default Settings)', 'Current IP Settings')) {
        $errorSaving = $True
        $errorMessage = "Can't overwrite $($profileDropdown.SelectedItem)"
    }
    If ($errorSaving) {
        $outputContentLabel.ForeColor = '0xaa0000'
        $outputContentLabel.Text = "Can't save - $errorMessage"
        Return "$($outputContentLabel.Text)"
    }
    $text = "Gateway: $($gatewayTextbox.Text)`nSubnetMask: $(Get-SubnetPrefix)`nIPAddress: $($ipAddressTextbox.Text)"
    $profiles = Get-IPProfiles
    If ($profiles -notcontains $profileNameTextbox.Text) {
        $profileDropdown.Items.Add($profileNameTextbox.Text)
    }
    Set-Content -Path "$profilesPath\$($profileNameTextbox.Text).txt" -Value $text
    $outputContentLabel.ForeColor = '0x00aa00'
    $outputContentLabel.Text = "Saved profile $($profileNameTextbox.Text)"
    Return ""
}

Function Apply-IPProfile {
    Param()
    $saveError = Save-IPProfile
    $outputContentLabel.ForeColor = '0xFD7F20'
    $outputContentLabel.Text = "Setting IP $ipAddress with subnet /$subnetPrefix and gateway $gateway."
    $ipAddress = $ipAddressTextbox.Text
    $gateway = $gatewayTextbox.Text
    $subnetPrefix = Get-SubnetPrefix
    If ($null -eq $adapterDropdown.SelectedItem -or $adapterDropdown.SelectedItem -eq "") {
        If ($saveError -eq "") {
            $outputContentLabel.Text = "Successfully saved profile.`nCan't apply. You must select an adapter."
        }
        Else {
            $outputContentLabel.ForeColor = '0xaa0000'
            $outputContentLabel.Text = "$saveError`nCan't apply. You must select an adapter."
        }
        Return
    }
    If ($profileDropdown.SelectedItem -eq 'DHCP (Default Settings)') {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\services\Tcpip\Parameters\Interfaces\$($network.InterfaceGuid)" -Name EnableDHCP -Value 1
        Set-NetIPInterface -InterfaceAlias $network.ifAlias -Dhcp Enabled
        & ipconfig /release
        & ipconfig /renew
        $outputContentLabel.ForeColor = '0x00aa00'
        $outputContentLabel.Text = "Set IP to DHCP."
    } Else {
        $saveError = Save-IPProfile
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\services\Tcpip\Parameters\Interfaces\$($network.InterfaceGuid)" -Name EnableDHCP -Value 0
        Set-NetIPInterface -InterfaceAlias $network.ifAlias -Dhcp Disabled
        $null = Remove-NetIPAddress -ErrorAction SilentlyContinue -InterfaceAlias $network.ifAlias -AddressFamily IPv4 -Confirm:$false
        $null = Remove-NetRoute -ErrorAction SilentlyContinue -InterfaceAlias $network.ifAlias -AddressFamily IPv4 -Confirm:$false
        Try {
            If ($gateway -eq "") {$null = New-NetIPAddress -IPAddress $ipAddress -InterfaceAlias $network.InterfaceAlias -PrefixLength $subnetPrefix -Confirm:$false}
            Else {$null = New-NetIPAddress -IPAddress $ipAddress -InterfaceAlias $network.InterfaceAlias -DefaultGateway $gateway -PrefixLength $subnetPrefix -Confirm:$false}
            If ($saveError) {$outputContentLabel.ForeColor = '0xFD7F20'} Else {$outputContentLabel.ForeColor = '0x00aa00'}
            $outputContentLabel.Text = "Set IP $ipAddress with subnet /$subnetPrefix and gateway $gateway.`n$saveError"
        } Catch {
            $outputContentLabel.ForeColor = '0xaa0000'
            $outputContentLabel.Text = "Failed to set IP $ipAddress with subnet /$subnetPrefix and gateway $gateway."
        }
    }
}

Function Convert-IpAddressToMaskLength([string] $dottedIpAddressString) {
    $result = 0; 
    # ensure we have a valid IP address
    [IPAddress] $ip = $dottedIpAddressString;
    $octets = $ip.IPAddressToString.Split('.');
    foreach($octet in $octets) {
        while(0 -ne $octet) {
            $octet = ($octet -shl 1) -band [byte]::MaxValue
            $result++; 
        }
    }
    return "$result";
}

# GUI Elements
Function Create-GUI {
    # Main Window
    $main_form = New-Object System.Windows.Forms.Form
    $main_form.Text = 'Network Profile Manager'
    $main_form.Width = 420
    $main_form.Height = 400

    # Network Adapter Dropdown
    $adapterLabel = New-Object System.Windows.Forms.Label
    $adapterLabel.Text = "Select Adapter"
    $adapterLabel.Location = New-Object System.Drawing.Point(20, 23)
    $adapterLabel.AutoSize = $true
    $main_form.Controls.Add($adapterLabel)

    $adapterDropdown = New-Object System.Windows.Forms.ComboBox
    $adapterDropdown.Location = New-Object System.Drawing.Point(100, 20)
    $adapterDropdown.Width = 280
    $adapters = Get-NetworkAdapters
    foreach ($adapter in $adapters) {
        $adapterDropdown.Items.Add($adapter.Name)
    }
    $adapterDropdown.Add_SelectedIndexChanged({
        Set-NetworkAdapter $adapterDropdown.SelectedItem
        # Optionally, refresh IP profile dropdown here
    })
    $main_form.Controls.Add($adapterDropdown)

    #Profile Selection Label
    $profileLabel = New-Object System.Windows.Forms.Label
    $profileLabel.Text = "Select Profile"
    $profileLabel.Location  = New-Object System.Drawing.Point(20,63)
    $profileLabel.AutoSize = $true
    $main_form.Controls.Add($profileLabel)

    #Profile Selection Dropdown
    $profileDropdown = New-Object System.Windows.Forms.ComboBox
    $profileDropdown.Width = 280
    $profiles = Get-IPProfiles
    Foreach ($profile in $profiles) {
        $profileDropdown.Items.Add($profile)
    }
    $profileDropdown.Location  = New-Object System.Drawing.Point(100,60)
    $profileDropdown.Add_TextChanged({
        $selectedProfile = Get-IPProfile -name $profileDropdown.SelectedItem
    })
    $main_form.Controls.Add($profileDropdown)

    #Profile Name Label
    $profileNameLabel = New-Object System.Windows.Forms.Label
    $profileNameLabel.Text = "Profile Name"
    $profileNameLabel.Location  = New-Object System.Drawing.Point(20,103)
    $profileNameLabel.AutoSize = $true
    $main_form.Controls.Add($profileNameLabel)

    #Profile Name Textbox
    $profileNameTextbox = New-Object System.Windows.Forms.TextBox
    $profileNameTextbox.Location  = New-Object System.Drawing.Point(100,100)
    $profileNameTextbox.Width = 140
    $main_form.Controls.Add($profileNameTextbox)

    #Gateway Label
    $gatewayLabel = New-Object System.Windows.Forms.Label
    $gatewayLabel.Text = "Gateway"
    $gatewayLabel.Location  = New-Object System.Drawing.Point(20,143)
    $gatewayLabel.AutoSize = $true
    $main_form.Controls.Add($gatewayLabel)

    #Gateway Textbox
    $gatewayTextbox = New-Object System.Windows.Forms.TextBox
    $gatewayTextbox.Text = ""
    $gatewayTextbox.Location = New-Object System.Drawing.Point(100,143)
    $gatewayTextbox.Width = 140
    $main_form.Controls.Add($gatewayTextbox)

    #Subnet Label
    $subnetLabel = New-Object System.Windows.Forms.Label
    $subnetLabel.Text = "Subnet"
    $subnetLabel.Location  = New-Object System.Drawing.Point(20,183)
    $subnetLabel.AutoSize = $true
    $main_form.Controls.Add($subnetLabel)

    #Subnet Textbox
    $subnetTextbox = New-Object System.Windows.Forms.TextBox
    $subnetTextbox.Text = ""
    $subnetTextbox.Location = New-Object System.Drawing.Point(100,183)
    $subnetTextbox.Width = 140
    $main_form.Controls.Add($subnetTextbox)

    #IPAddress Label
    $ipAddressLabel = New-Object System.Windows.Forms.Label
    $ipAddressLabel.Text = "IP Address"
    $ipAddressLabel.Location  = New-Object System.Drawing.Point(20,223)
    $ipAddressLabel.AutoSize = $true
    $main_form.Controls.Add($ipAddressLabel)

    #IPAddress Textbox
    $ipAddressTextbox = New-Object System.Windows.Forms.TextBox
    $ipAddressTextbox.Text = ""
    $ipAddressTextbox.Location = New-Object System.Drawing.Point(100,223)
    $ipAddressTextbox.Width = 140
    $main_form.Controls.Add($ipAddressTextbox)

    #New Profile Button
    $newProfileButton = New-Object System.Windows.Forms.Button
    $newProfileButton.Location = New-Object System.Drawing.Size(260,100)
    $newProfileButton.Size = New-Object System.Drawing.Size(120,20)
    $newProfileButton.Text = "+ New Profile"
    $main_form.Controls.Add($newProfileButton)
    $newProfileButton.Add_Click({
        New-IPProfile
    })

    #Apply Profile Button
    $applyProfileButton = New-Object System.Windows.Forms.Button
    $applyProfileButton.Location = New-Object System.Drawing.Size(260,140)
    $applyProfileButton.Size = New-Object System.Drawing.Size(120,20)
    $applyProfileButton.Text = "Apply Profile"
    $main_form.Controls.Add($applyProfileButton)
    $applyProfileButton.Add_Click({
        Apply-IPProfile
    })

    #Save Profile Button
    $saveProfileButton = New-Object System.Windows.Forms.Button
    $saveProfileButton.Location = New-Object System.Drawing.Size(260,180)
    $saveProfileButton.Size = New-Object System.Drawing.Size(120,20)
    $saveProfileButton.Text = "Save Profile"
    $main_form.Controls.Add($saveProfileButton)
    $saveProfileButton.Add_Click({
        $null = Save-IPProfile
    })

    #Cancel Profile Button
    $cancelProfileButton = New-Object System.Windows.Forms.Button
    $cancelProfileButton.Location = New-Object System.Drawing.Size(260,220)
    $cancelProfileButton.Size = New-Object System.Drawing.Size(120,20)
    $cancelProfileButton.Text = "Cancel Changes"
    $main_form.Controls.Add($cancelProfileButton)
    $cancelProfileButton.Add_Click({
        Get-IPProfile -name $profileDropdown.SelectedItem
        $outputContentLabel.ForeColor = '0x00aa00'
        $outputContentLabel.Text = "Discarded changes."
    })


    #Output (Bottom) Label
    $outputLabel = New-Object System.Windows.Forms.Label
    $outputLabel.Text = "Output log"
    $outputLabel.Location  = New-Object System.Drawing.Point(20,280)
    $outputLabel.AutoSize = $true
    $main_form.Controls.Add($outputLabel)

    #Output (Bottom) Content Label
    $outputContentLabel = New-Object System.Windows.Forms.Label
    $outputContentLabel.Text = "Loaded window"
    $outputContentLabel.ForeColor = '0x00aa00'
    $outputContentLabel.Location  = New-Object System.Drawing.Point(20,300)
    $outputContentLabel.Width = 380
    $outputContentLabel.Height = 60
    $main_form.Controls.Add($outputContentLabel)

    # Show Dialog
    $main_form.ShowDialog()
}

# Script Execution
Create-GUI
