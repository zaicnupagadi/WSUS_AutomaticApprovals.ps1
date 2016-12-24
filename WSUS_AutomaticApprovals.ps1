<#
.SYNOPSIS
WSUS_AutomaticApprovals.ps1 - Script that does automatic approvals for Pilot and Standard groups in intervals.

.DESCRIPTION 
Script helps in approval cycle - approving updates firstly to defined "pilot" groups, and later after certain time, appying these to "standard" groups, and doing new approval for "pilot".

Pilot groups need to have "pilot" in name, as the same standard need to have "standard".

HOW IT WORKS:
Script checks if relevant .csv file exists.

If CSV does NOT exist (if dry run):
Script does approval process just for pilot group.

if CSV exists:
Script checks what was the last time span for updates approved to a "pilot" group.
For that time span it does approval for "standard" targer groups.
Second approval cycle is being done on "pilot" target groups (start time: last sync time, end time: date the sript is triggered)

.OUTPUTS
Verbose option
CSV file

.PARAMETER range
Parameter needed for specifiyng scope of target groups - in this example "Servers" and "Workstations"

.PARAMETER verbose
Gemerates detailed output on the screen.

.EXAMPLE
.\WSUS_AutomaticApprovals.ps1 -range "Servers" -Verbose
This command will do updates on all target groups with "Servers" in name, write everything to CSV file and show detailed information on the screen.

.EXAMPLE
.\WSUS_AutomaticApprovals.ps1 -Range "Workstations"
This command will do updates on all target groups with "Workstations" in name and write everything to CSV file.

.LINK
https://paweljarosz.wordpress.com/2016/12/20/powershell-script-for-auto-approving-wsus-updates-for-pi

.NOTES
Written By: Pawel Jarosz
Website:	http://paweljarosz.wordpress.com
GitHub:     https://github.com/zaicnupagadi
Technet:    https://gallery.technet.microsoft.com/scriptcenter/site/mydashboard


Change Log
V1.00, 20/12/2016 - Initial version

#>


Param(
  [Parameter(Mandatory=$true, HelpMessage="Available switches are 'Workstations' or 'Servers'")] [string]$range

)

Function ApproveUpdates ($TargetGroup, $StartDate, $EndDate, $Range) {
$report = @()

$Current_Date_Formated = (get-date -Format ‘MM\/dd\/yyyy’)
$Next_Approval_Date_Raw = (Get-Date).AddDays(14)
$Next_Approval_Date_Formated = '{0:MM\/dd\/yyyy}' -f $Next_Approval_Date_Raw

$updatescope = New-Object Microsoft.UpdateServices.Administration.UpdateScope

ForEach ($TG in $TargetGroup) {

$updatescope.FromCreationDate = $StartDate
$updatescope.ToCreationDate = $EndDate

$Number_Of_Updates = ($wsus.GetUpdates($UpdateScope) | Measure-Object).count

    $wsus.GetUpdates($UpdateScope) | ForEach {

      Write-Verbose ("Approving {0} for {1}" -f $_.Title,$TG.Name)
        if($_.RequiresLicenseAgreementAcceptance) {
        $_.AcceptLicenseAgreement()
        Write-Verbose -Message "License accepted for $($_.Title)" -Verbose
        }
      $_.Approve('Install',$TG) | Out-Null
      }

    $obj = [PSCustomObject]@{
    UpdateRange = $Range
    TargetGroupName = $TG.Name
    StartPatchDate = $StartDate
    EndPatchDate = $EndDate
    NumberOfUpdates = $Number_Of_Updatess
    CurrentDate = $Current_Date_Formated
    NextApprovalDate = $Next_Approval_Date_Formated
}
$report += $obj
}
$report | export-csv $CSVFile -Delimiter ";" -Append
}


if ($range -eq "Workstations" -or $range -eq "Servers"){

Write-Verbose "Process of updates approval for $range has been triggered..."

$wsus = Get-WsusServer
$CSVFileName = $range+"UpdateTimes.csv"
$CSVPath = 'c:\'
$CSVFile = "$CSVPath$CSVFileName"

$Current_Date = (get-date -Format ‘MM\/dd\/yyyy’)

    if (!(Test-Path $CSVFile)) {

    Write-Verbose "File $CSVFileName does not exist i given path, starting initial approval..."
    $InitialApproval = $true
    $Group = $wsus.GetComputerTargetGroups() | where {$_.Name -match "$range" -and $_.Name -match "Pilot" }
    Write-Verbose "Starting approval of updates for time range 01/01/2016 - $Current_Date"

    Write-Verbose "Starting approval of Pilot groups for period 01/01/2000 - $Current_Date"
    ApproveUpdates $Group "01/01/2000" $Current_Date $range

    } else {

    Write-Verbose "File $CSVFileName exists, importing..."
    $ImportCsv = Import-Csv $CSVFile -Delimiter ";"

    $PilotLastSyncRecords = $ImportCsv | ? {$_.TargetGroupName -match "Pilot"} | sort { [datetime]$_.NextApprovalDate } -Descending

    if ($Current_Date -eq $PilotLastSyncRecords[0].NextApprovalDate){

    $SPD = $PilotLastSyncRecords[0].StartPatchDate
    $EPD = $PilotLastSyncRecords[0].EndPatchDate
    $CPD = $PilotLastSyncRecords[0].CurrentDate

    Write-Verbose "Last time of synchronization time was $CPD"

    $GroupPilot = $wsus.GetComputerTargetGroups() | where {$_.Name -match "$range" -and $_.Name -match "Pilot" }
    $GroupStandard = $wsus.GetComputerTargetGroups() | where {$_.Name -match "$range" -and $_.Name -match "Standard" }
    
    Write-Verbose "Starting approval of Standard groups for period $SPD  - $EPD"
    ApproveUpdates $GroupStandard $SPD $EPD $range

    Write-Verbose "Starting approval of Pilot groups for period $EPD - $Current_Date"
    ApproveUpdates $GroupPilot $EPD $Current_Date $range
    
    } else {
    Write-Output "Today is not the day of next approval cycle."
    }
    
    }

} else {
write-Output "Wrong 'range' parameter has been provided, it should be 'Servers' either 'Workstations'."
}