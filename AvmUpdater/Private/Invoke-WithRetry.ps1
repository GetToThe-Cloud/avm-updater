function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Executes a script block with exponential back-off retry and configurable timeout.
    .PARAMETER ScriptBlock
        The script block to execute.
    .PARAMETER MaxRetries
        Maximum number of retry attempts. Default: 3.
    .PARAMETER DelaySeconds
        Base delay in seconds between retries (doubles each attempt). Default: 2.
    .PARAMETER OperationName
        Friendly name for log messages.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 2,
        [string]$OperationName = 'operation'
    )

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            return & $ScriptBlock
        } catch {
            if ($attempt -ge $MaxRetries) {
                Write-Warning "[$OperationName] Failed after $MaxRetries attempts: $_"
                throw
            }
            $wait = $DelaySeconds * [Math]::Pow(2, $attempt - 1)
            Write-Verbose "[$OperationName] Attempt $attempt failed, retrying in ${wait}s: $_"
            Start-Sleep -Seconds $wait
        }
    }
}
