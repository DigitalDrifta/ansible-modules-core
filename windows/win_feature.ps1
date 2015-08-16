#!powershell
# This file is part of Ansible.
#
# Copyright 2014, Paul Durivage <paul.durivage@rackspace.com>
#
# Ansible is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ansible is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Ansible.  If not, see <http://www.gnu.org/licenses/>.

# WANT_JSON
# POWERSHELL_COMMON

Import-Module Servermanager;

$params = Parse-Args $args;

$result = New-Object PSObject -Property @{
    changed = $false
}

If ($params.name) {
    $name = $params.name -split ',' | % { $_.Trim() }
}
Else {
    Fail-Json $result "mising required argument: name"
}

If ($params.state) {
    $state = $params.state.ToString().ToLower()
    If (($state -ne 'present') -and ($state -ne 'absent')) {
        Fail-Json $result "state is '$state'; must be 'present' or 'absent'"
    }
}
Elseif (!$params.state) {
    $state = "present"
}

If ($params.restart) {
    $restart = $params.restart | ConvertTo-Bool
}
Else {
    $restart = $false
}

If ($params.include_sub_features) {
    $includesubfeatures = $params.include_sub_features | ConvertTo-Bool
}
Else {
    $includesubfeatures = $false
}

If ($params.include_management_tools) {
    $includemanagementtools = $params.include_management_tools | ConvertTo-Bool
}
Else {
    $includemanagementtools = $false
}

If ($params.source) {
    $source = $params.source.ToString().ToLower()
    If (!Test-Path $source) {
	    Fail-Json $result "Source is $source; must be a drive (D:\sources\sxs) or network share (\\IP\Share\sources\sxs)'"
    }
}

If ($state -eq "present") {
    try {
        If (Get-Command "Install-WindowsFeature" -ErrorAction SilentlyContinue) {
            if ($source) {
		        $featureresult = Install-WindowsFeature -Name $name -Restart:$restart -IncludeAllSubFeature:$includesubfeatures -IncludeManagementTools:$includemanagementtools -Source:$source -ErrorAction SilentlyContinue
	        }
	        else {
		        $featureresult = Install-WindowsFeature -Name $name -Restart:$restart -IncludeAllSubFeature:$includesubfeatures -IncludeManagementTools:$includemanagementtools -ErrorAction SilentlyContinue
	        }
	    }
	    ElseIf (Get-Command "Add-WindowsFeature" -ErrorAction SilentlyContinue) {
	        if ($source) {
		        $featureresult = Add-WindowsFeature -Name $name -Restart:$restart -IncludeAllSubFeature:$includesubfeatures -Source:$source -ErrorAction SilentlyContinue
	        }
            else {
	            $featureresult = Add-WindowsFeature -Name $name -Restart:$restart -IncludeAllSubFeature:$includesubfeatures -ErrorAction SilentlyContinue
	        }
	    }
	    Else {
	        Fail-Json $result "Not supported on this version of Windows"
	    }
    }
    catch {
        Fail-Json $result $_.Exception.Message
    }
}
ElseIf ($state -eq "absent") {
    try {
        If (Get-Command "Uninstall-WindowsFeature" -ErrorAction SilentlyContinue) {
            $featureresult = Uninstall-WindowsFeature -Name $name -Restart:$restart -ErrorAction SilentlyContinue
        }
        ElseIf (Get-Command "Remove-WindowsFeature" -ErrorAction SilentlyContinue) {
            $featureresult = Remove-WindowsFeature -Name $name -Restart:$restart -ErrorAction SilentlyContinue
        }
        Else {
            Fail-Json $result "Not supported on this version of Windows"
        }
    }
    catch {
        Fail-Json $result $_.Exception.Message
    }
}

# Loop through results and create a hash containing details about
# each role/feature that is installed/removed
$installed_features = @()
#$featureresult.featureresult is filled if anything was changed
If ($featureresult.FeatureResult) {
    ForEach ($item in $featureresult.FeatureResult) {
        $message = @()
        ForEach ($msg in $item.Message) {
            $message += New-Object PSObject -Property @{
                message_type = $msg.MessageType.ToString()
                error_code = $msg.ErrorCode
                text = $msg.Text
            }
        }
        $installed_features += New-Object PSObject -Property @{
            id = $item.Id
            display_name = $item.DisplayName
            message = $message
            restart_needed = $item.RestartNeeded.ToString() | ConvertTo-Bool
            skip_reason = $item.SkipReason.ToString()
            success = $item.Success.ToString() | ConvertTo-Bool
        }
    }
    $result.changed = $true
}

Set-Attr $result "feature_result" $installed_features
Set-Attr $result "success" ($featureresult.Success.ToString() | ConvertTo-Bool)
Set-Attr $result "exitcode" $featureresult.ExitCode.ToString()
Set-Attr $result "restart_needed" ($featureresult.RestartNeeded.ToString() | ConvertTo-Bool)

If ($result.success) {
    Exit-Json $result
}
ElseIf ($state -eq "present") {
    Fail-Json $result "Failed to add feature"
}
Else {
    Fail-Json $result "Failed to remove feature"
}
