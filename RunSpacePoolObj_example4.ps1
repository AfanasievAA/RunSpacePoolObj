# By Andrew Afanasiev (AFanasievAA@yandex.ru)
# Example #4 of RunSpacePoolObj usage
# This script will get all domain  controllers in domain and seeks fastest measuring time for each to answer

Try {
    $Global:ScriptRootFolderRunPath = Split-Path (Get-Variable MyInvocation -Scope 0).Value.MyCommand.Path
    $Global:FLGScriptMode = $true
    $Global:FLGEXEMode = $false
} Catch {
    # If above fails - we are running from exe (compiled mode)
    $Global:ScriptRootFolderRunPath = (Get-Location).Path
    $Global:FLGScriptMode = $false
    $Global:FLGEXEMode = $true
}

# Including RunSpacePoolObj object
. "$($Global:ScriptRootFolderRunPath)\RunSpacePoolObj.ps1"
# Maximum number of threads running 
$RunSpacePoolObj.MaxThreads = 20
# Each thread timeout.
$RunSpacePoolObj.JobTimeout = New-TimeSpan -Seconds 3

# Main scriptblock to run in parallel. Some of the threads will be timed out and some of them will be completed successfully 
$RunSpacePoolObj.ScriptBlock = {
    param ($DCHostname)

    $timing = (Measure-Command {
        Get-ADUser Administrator -Server $DcHostName
    }).TotalMilliseconds

    Write-Information ('{0:d5}' -f [int]([math]::Round($timing)))

}
# Initialize shoud be run after any changing in RunSpacePoolObj parameters
$RunSpacePoolObj.Initialize()

# Get all Domain Controllers in a forest
$AllDCs = Get-ADDomainController -Filter { IsReadOnly -eq $false } | Select-Object Name,Hostname,Ipv4address,isGlobalCatalog,Site,Forest,OperatingSystem

# Running DC check thread for each DC in the list
ForEach($DC in ($AllDCs | Sort-Object Site,HostName)) {
    $JobId = $RunSpacePoolObj.RunJob(($DC.Hostname))
}

# The main cycle while there are jobs in queue or running
while ($RunSpacePoolObj.JobsCounter.Queued -gt 0 -or $RunSpacePoolObj.JobsCounter.Running -gt 0) {
    # Sleeping for 1 second
    Start-Sleep -Seconds 1
    # Call for this procedure updates running jobs status and issues timeout for long jobs
    $RunSpacePoolObj.GetCurrentStatus()
    # IF any change detected after last GetCurrentStatus call - print current status
    if ($RunSpacePoolObj.JobsCounter.Changed) {
        Write-Host "Queued: $($RunSpacePoolObj.JobsCounter.Queued); Running: $($RunSpacePoolObj.JobsCounter.Running); Completed: $($RunSpacePoolObj.JobsCounter.Completed); TimedOut: $($RunSpacePoolObj.JobsCounter.TimedOut); Failed: $($RunSpacePoolObj.JobsCounter.Failed);"
    }
}
# Formatting final results. Taking only completed jobs and converting time taken to int
$result = $RunSpacePoolObj.Jobs |  Where-Object State -eq "Completed" | Select-Object @{Name="Server"; Expression={$_.Arguments[0]}},@{Name="TimeTaken"; Expression={[convert]::ToInt32($_.Information,10)}} | Sort-Object TimeTaken
$result | Format-Table
# Closing RunSpacePool
$RunSpacePoolObj.Close()

