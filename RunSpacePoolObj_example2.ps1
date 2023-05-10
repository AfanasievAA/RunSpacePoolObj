# By Andrew Afanasiev (AFanasievAA@yandex.ru)
# Example #2 of RunSpacePoolObj usage
# This script will get all domain controllers in domain and test them for connectivity in parallel
# If you have more than 20 DCs (like I do), you'll notice how fast this script is running compared to normal unparalleled mode
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
$RunSpacePoolObj.JobTimeout = New-TimeSpan -Seconds 15

# Main scriptblock to run in parallel. Some of the threads will be timed out and some of them will be completed successfully 
$RunSpacePoolObj.ScriptBlock = {
    param ($DCHostname, $DCIP)
    Try { 
        # To test a DC we'll get Administrator user params
        $ag = Get-ADUser Administrator -Server ($DCHostname)
        # If no errors are thrown - connection is ok        
        Write-Information "$($DCHostname) ($($DCIP)) is ok" 
    }
    Catch {
        # If errors a thrown - connection failed
        Write-Information "$($DCHostname) ($($DCIP)) NOT ok. $($_.Exception.Message)"
    }
}
# Initialize shoud be run after any changing in RunSpacePoolObj parameters
$RunSpacePoolObj.Initialize()

# Get all Domain Controllers in a forest
$AllDCs = Get-ADDomainController -Filter * | Select-Object Name,Hostname,Ipv4address,isGlobalCatalog,Site,Forest,OperatingSystem

# Running DC check thread for each DC in the list
ForEach($DC in ($AllDCs | sort Site,HostName)) {
    $JobId = $RunSpacePoolObj.RunJob(($DC.Hostname, $DC.Ipv4address))
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
# Printing out final results
$RunSpacePoolObj.Jobs | Select-Object Arguments,State,Information | Format-Table
# Closing RunSpacePool
$RunSpacePoolObj.Close()

