# By Andrew Afanasiev (AFanasievAA@yandex.ru)
# Example #1 of RunSpacePoolObj usage
# Sample script to run in parralel. Will pause for random ammount of time and set timeout so some of threads will be termindated before they complete.
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
$RunSpacePoolObj.MaxThreads = 15
# Each thread timeout.
$RunSpacePoolObj.JobTimeout = New-TimeSpan -Seconds 15

# Main scriptblock to run in parallel. Some of the threads will be timed out and some of them will be completed successfully 
$RunSpacePoolObj.ScriptBlock = {
    param ($pauseTimer, $text)
    Start-Sleep -Seconds $pauseTimer
    # Write-Information returns a value from Job
    Write-Information "$($pauseTimer) seconds passed. $($text)"
}
# Initialize shoud be run after any changing in RunSpacePoolObj parameters
$RunSpacePoolObj.Initialize()

# Running 25 threads each pausing random time from 0 to 30 seconds
for ($i=0; $i -le 25; $i++) {
    $pauseTimer = Get-Random -Maximum 30
    $someText = "This is a random text"
    # Notice that scriptblock parameters are passed as array of strings
    $JobId = $RunSpacePoolObj.RunJob(($pauseTimer, $someText))
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
$RunSpacePoolObj.Jobs | Select-Object Id,Started,Ended,State,Information | Format-List
# Closing RunSpacePool
$RunSpacePoolObj.Close()

