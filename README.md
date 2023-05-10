# RunSpacePoolObj
Powershell object used to easy run/track parralel processes with RunSpacePool technique. 
Allows you to easily run, track powershell scriptblocks in parralel with timeout feature and return values

.PARAMETER ScriptBlock
  Script to be run in parallel with some imput parameters. Output is carried out by Write-Information function
  DON'T USE Write-Debug in your parallel scripts, as it will interfere with script inner procedure
.PARAMETER MaxThreads
  Maxium number of threads allowed to run, all the rest will be kept in queue 
.PARAMETER JobTimeout
  Maximum allowed timing of the job defined as TimeSpan (New-TimeSpan).
.PARAMETER Jobs
  Arraylist of current running/queued/completed jobs. Each Job object consist of
    Id          - Id (INT32) of the Job
    Pipe        - Powershell object of the job
    Handle      - Job handle
    Started     - Time Job was started
    Ended       - TIme Job was finished
    State       - Current state of Job
    Arguments   - Current arguments passed to a script
    Information - Return infromation with a script results
.PARAMETER JobCounter
  CustomObject with counters for current jobs. Updated when called procedure GetCurrentStatus
    Queued      - Number of queued jobs waiting execution
    Running     - Number of running jobs
    Completed   - Number of finished without errors jobs
    TimedOut    - Number of timedout jobs exceeding JobTimeout limit terminaded before they complete
    Changed     - Just a flag indicating that something is changed after last call for GetCurrentStatus procedure
.FUNCTION Initialize
    Initialize an object. Must be called prior to running Jobs and in any change in parameters
.FUNCTION RunJob
    Runs a new job in a pool. Argument only one - array of strings, that'll be passed to a Job
.FUNCTION RemoveJob
    Removes job from Jobs arraylist by it's ID
.FUNCTION GetCurrentStatus
    Main function when jobs are running. Called every second of few to check what jobs are finished. Updates Jobs and JobCounter params
.FUNCTION Close
    Closes RunSpacePool to free meomory
.EXAMPLE
    $RunSpacePoolObj.MaxThreads = 3
    $RunSpacePoolObj.JobTimeout = New-TimeSpan -Seconds 15
    $RunSpacePoolObj.ScriptBlock = {
        param ($pauseTimer, $text)
        Start-Sleep -Seconds $pauseTimer
        Write-Information "$($pauseTimer) seconds passed. $($text)"
    }
    $RunSpacePoolObj.Initialize()
    $RunSpacePoolObj.RunJob(((Get-Random -Maximum 30), "Hello world!"))
    $RunSpacePoolObj.RunJob(((Get-Random -Maximum 30), "Hello world!"))
    $RunSpacePoolObj.RunJob(((Get-Random -Maximum 30), "Hello world!"))
    $RunSpacePoolObj.RunJob(((Get-Random -Maximum 30), "Hello world!"))
    $RunSpacePoolObj.RunJob(((Get-Random -Maximum 30), "Hello world!"))
    while ($RunSpacePoolObj.JobsCounter.Queued -gt 0 -or $RunSpacePoolObj.JobsCounter.Running -gt 0) {
        Start-Sleep -Seconds 1
        $RunSpacePoolObj.GetCurrentStatus()
        if ($RunSpacePoolObj.JobsCounter.Changed) {
            Write-Host "Queued: $($RunSpacePoolObj.JobsCounter.Queued); Running: $($RunSpacePoolObj.JobsCounter.Running); Completed: $($RunSpacePoolObj.JobsCounter.Completed); TimedOut: $($RunSpacePoolObj.JobsCounter.TimedOut); Failed: $($RunSpacePoolObj.JobsCounter.Failed);"
        }
    }
    $RunSpacePoolObj.Jobs | Select-Object Id,Started,Ended,State,Information | Format-List
    $RunSpacePoolObj.Close()
