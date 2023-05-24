#requires -version 5.0
<#
.SYNOPSIS
  Powershell object used to easy run/track parralel processes with RunSpacePool technique. 
.DESCRIPTION
  Allows you to easily run, track powershell scriptblocks in parralel with timeout feature and return values
.NOTES
  Version:        0.3
  Author:         Andrew Afanasiev
  Date:           23.05.2023
  Purpose/Change: Initial script development
  Contacts:       AfanasievAA@yandex.ru

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
    Errors      - Returns errors encountered during run
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
#>

$Global:RunSpacePoolObj = [PSCustomObject]@{
    # Main scripblock to execute in RSP
    ScriptBlock = {
    }
    # Don't touch this variable. Used for inner purposes
    JobScript = { }
    # Threads count
    MaxThreads = 10
    # Jobs counter
    JobCounter = 0
    # Time after jobs will be terminaded
    JobTimeout = New-TimeSpan -Seconds 1200
    # Variable for storing current jobs status
    #JobStatus = [hashtable]::Synchronized(@{})
    # Jobs array list
    Jobs = New-Object System.Collections.arrayList
    JobsCounter =  [PSCustomObject]@{
        Queued = 0
        Running = 0
        Completed = 0
        TimedOut = 0
        Failed = 0
    }
    RunspacePool = $null
}

$Global:RunSpacePoolObj | Add-Member -MemberType ScriptMethod -Name "Initialize" -Value {
    if ($this.JobTimeout.getType().Name -ne "TimeSpan") {
        Throw "Cannot initialize RunSpacePoolObj as JobTimeOut is not of correct type (use TimeSpan to define it)"
    }
    $this.JobCounter = 0
# Write-Debug is used to get thread timing
$this.JobScript =
@"
    &{ 
        `$DebugPreference = 'Continue'
        Write-Debug "Start(Ticks) = `$((get-date).Ticks)"
    }
    
    & { $($this.ScriptBlock) } @args
    
    &{
        `$DebugPreference = 'Continue' 
        Write-Debug "End(Ticks) = `$((get-date).Ticks)"
    }
"@
    
    # Creating RunSpacePool
    $this.RunSpacePool = [runspacefactory]::CreateRunspacePool(1, $this.MaxThreads)    
    $this.RunSpacePool.CleanupInterval = [timespan]::FromSeconds(1)
    # Default	0	- Use the default options: UseNewThread for local Runspace, ReuseThread for local RunspacePool, server settings for remote Runspace and RunspacePool
    # ReuseThread	2	- Creates a new thread for the first invocation and then re-uses that thread in subsequent invocations.
    # UseCurrentThread	3	- Doesn't create a new thread; the execution occurs on the thread that calls Invoke.
    # UseNewThread	1	- Creates a new thread for each invocation
    #$Runspacepool.ThreadOptions = 1
    $this.RunSpacePool.Open()
    # New jobjs arraylist
    $this.Jobs = New-Object System.Collections.arrayList
    $this.JobsCounter =  [PSCustomObject]@{
        Queued = 0
        Running = 0
        Completed = 0
        TimedOut = 0
        Failed = 0
        Changed = $false
    }
}

# Running a new Job. Returns JobID (INT32)
$Global:RunSpacePoolObj | Add-Member -MemberType ScriptMethod -Name "RunJob" -Value {
    param ([string[]]$ArgumentsArray)
    $PowerShell = [powershell]::Create()
    $PowerShell.RunspacePool = $this.RunspacePool
    # Calling a ScriptBlock with 2 arguments. First - job number, second - $hash variable
    $ScriptAdded = $PowerShell.AddScript($this.JobScript)
    foreach ($argument in $ArgumentsArray) {
        $null = $ScriptAdded.AddArgument($argument)
    }
    $JobId = $this.JobCounter++
    $null = $this.Jobs.add([PSCustomObject]@{
        Id = $JobID
        Pipe = $PowerShell
        Handle = $PowerShell.BeginInvoke()
        Started = $null
        Ended = $null
        State = "Queued"
        Arguments = $ArgumentsArray
        Information = $null
        Errors = $null
    })
    $this.UpdateJobCounter()
    return ,$JobID
}

# Removing Job from array
$Global:RunSpacePoolObj | Add-Member -MemberType ScriptMethod -Name "RemoveJob" -Value {
    param ([int32]$JobID)
    $element = ($RunSpacePoolObj.Jobs | Where-Object ID -eq 25)
    $RunSpacePoolObj.Jobs.Remove($element)
}

$Global:RunSpacePoolObj | Add-Member -MemberType ScriptMethod -Name "UpdateJobCounter" -Value {
    $this.JobsCounter.Failed = ($RunSpacePoolObj.Jobs | Where-Object State -eq "Failed" | Measure-Object).Count
    $this.JobsCounter.Completed = ($RunSpacePoolObj.Jobs | Where-Object State -eq "Completed" | Measure-Object).Count
    $this.JobsCounter.Queued = ($RunSpacePoolObj.Jobs | Where-Object State -eq "Queued" | Measure-Object).Count
    $this.JobsCounter.Running = ($RunSpacePoolObj.Jobs | Where-Object State -eq "Running" | Measure-Object).Count
    $this.JobsCounter.TimedOut = ($RunSpacePoolObj.Jobs | Where-Object State -eq "TimedOut" | Measure-Object).Count
}

$Global:RunSpacePoolObj | Add-Member -MemberType ScriptMethod -Name "GetCurrentStatus" -Value {
    $this.JobsCounter.Changed = $false
    $StartTicksRG = "Start\(Ticks\) = (\d+)"
    $EndTicksRG = "End\(Ticks\) = (\d+)"

    foreach ($Job in $this.Jobs) {
        # Marking jobs that are running
        if (($Job.Started -eq $null) -and ($Job.pipe.Streams.Debug[0].Message -match $StartTicksRG)) {
            $Job.Started = [Datetime]::MinValue + [TimeSpan]::FromTicks($Matches[1])
            $Job.State = "Running"
            $this.JobsCounter.Changed = $true
        }
        
        # if completed without errors
        if ($Job.Handle.IsCompleted -and $null -eq $Job.Ended -and -Not $Job.Pipe.HadErrors) {
            if ($Job.pipe.Streams.Debug[-1].Message -match $EndTicksRG) {
                $EndTicks = $Matches[1]    
                $Job.Ended = [Datetime]::MinValue + [TimeSpan]::FromTicks($EndTicks)
            } else {
                $Job.Ended = $Job.Started
            }
            $Job.State = "Completed"
            $Job.Information = $Job.pipe.Streams.Information
            $Job.Pipe.EndInvoke($Job.Handle)
            $Job.Pipe.Dispose()
            $this.JobsCounter.Changed = $true
        } 

        #Job running, exceeded max run time. Record job data and stop thread.
        if ($Job.State -eq 'Running' -and ($Job.Started) -and (-not ($Job.Handle.IsCompleted) ) -and (get-date) -gt ($Job.Started + $this.JobTimeout)) {
            $Job.Ended = (Get-Date)
            $null = $Job.Pipe.BeginStop($null,$Job.Handle)
            $Job.State = 'TimedOut'
        } elseif ($Job.State -eq 'Stopping' -and $Job.pipe.InvocationStateInfo.State -eq "Stopped") {
            $Job.Pipe.Dispose()
            $Job.State = 'TimedOut'
			$this.JobsCounter.Changed = $true
		}        

        # If job finished with errors and there are error stream (not just timed out)
        if ($Job.Pipe.HadErrors -and $Job.pipe.Streams.Error) {
            $Job.State = "Failed"
            $Job.Errors = $Job.pipe.Streams.Error.Exception.Message
            $Job.Pipe.Dispose()
            $this.JobsCounter.Changed = $true
        } 

    }
    # Updating job counter
    if ($this.JobsCounter.Changed = $true) {
        $this.UpdateJobCounter()
    }
}
# Closing runspacepool object after everything is done
$Global:RunSpacePoolObj | Add-Member -MemberType ScriptMethod -Name "Close" -Value {
    if ($this.RunspacePool -is [System.Object]) {
        $null = $this.RunspacePool.BeginClose($null, $null)
    }
    $this.RunspacePool = $null
}