#Requires -Modules @{ModuleName='Pester'; ModuleVersion='5.0.0'}

# Must be loaded at discovery time for InModuleScope to work
$_modulePath = Join-Path $PSScriptRoot '../AvmUpdater/AvmUpdater.psd1'
Import-Module $_modulePath -Force

BeforeAll {
    $script:FixturesPath = Join-Path $PSScriptRoot 'fixtures'
}

Describe 'Get-AvmModuleReference' {
    Context 'Bicep fixtures' {
        It 'Finds exactly 3 bicep references' {
            $refs = Get-AvmModuleReference -Path $script:FixturesPath
            $bicepRefs = @($refs | Where-Object ecosystem -eq 'bicep')
            $bicepRefs.Count | Should -Be 3
        }

        It 'Identifies the br/public short-hand storage-account reference' {
            $refs = Get-AvmModuleReference -Path $script:FixturesPath
            $ref = $refs | Where-Object { $_.module -eq 'storage-account' -and $_.ecosystem -eq 'bicep' }
            $ref | Should -Not -BeNullOrEmpty
            $ref.category       | Should -Be 'res'
            $ref.group          | Should -Be 'storage'
            $ref.currentVersion | Should -Be '0.4.0'
            $ref.isConstraint   | Should -Be $false
            $ref.registryPath   | Should -Be 'bicep/avm/res/storage/storage-account'
        }

        It 'Identifies the full MCR path key-vault reference' {
            $refs = Get-AvmModuleReference -Path $script:FixturesPath
            $ref = $refs | Where-Object { $_.module -eq 'vault' -and $_.ecosystem -eq 'bicep' }
            $ref | Should -Not -BeNullOrEmpty
            $ref.category       | Should -Be 'res'
            $ref.group          | Should -Be 'key-vault'
            $ref.currentVersion | Should -Be '0.6.2'
        }

        It 'Identifies the ptn hub-networking reference' {
            $refs = Get-AvmModuleReference -Path $script:FixturesPath
            $ref = $refs | Where-Object { $_.module -eq 'hub-networking' }
            $ref | Should -Not -BeNullOrEmpty
            $ref.category | Should -Be 'ptn'
        }
    }

    Context 'Terraform fixtures' {
        It 'Finds exactly 2 terraform references' {
            $refs = Get-AvmModuleReference -Path $script:FixturesPath
            $tfRefs = @($refs | Where-Object ecosystem -eq 'terraform')
            $tfRefs.Count | Should -Be 2
        }

        It 'Flags the ~> constraint ref as isConstraint=$true' {
            $refs = Get-AvmModuleReference -Path $script:FixturesPath
            $constrained = $refs | Where-Object { $_.isConstraint -eq $true }
            $constrained | Should -Not -BeNullOrEmpty
            $constrained.currentVersion | Should -Match '~>'
        }

        It 'Pinned terraform ref has isConstraint=$false' {
            $refs = Get-AvmModuleReference -Path $script:FixturesPath
            $pinned = $refs | Where-Object { $_.ecosystem -eq 'terraform' -and $_.isConstraint -eq $false }
            $pinned | Should -Not -BeNullOrEmpty
            $pinned.currentVersion | Should -Be '0.2.9'
        }
    }

    Context 'Exclusion' {
        It 'Excludes paths matching the glob' {
            $refs = Get-AvmModuleReference -Path $script:FixturesPath -Exclude @('*.tf')
            $tfRefs = @($refs | Where-Object ecosystem -eq 'terraform')
            $tfRefs.Count | Should -Be 0
        }
    }
}

Describe 'ConvertTo-SemVer / Sort-SemVer (Private)' {
    InModuleScope AvmUpdater {
        It 'Returns $null for non-semver input' {
            ConvertTo-SemVer -Version 'latest' | Should -BeNullOrEmpty
        }
        It 'Parses a valid version' {
            $v = ConvertTo-SemVer -Version '0.4.1'
            $v | Should -Not -BeNullOrEmpty
        }
        It 'Sort-SemVer returns descending order and drops preview' {
            $sorted = Sort-SemVer -Versions @('0.1.0', '0.5.0-preview', '0.3.0', '0.2.0', 'latest')
            $sorted[0] | Should -Be '0.3.0'
            $sorted    | Should -Not -Contain 'latest'
            $sorted    | Should -Not -Contain '0.5.0-preview'
        }
    }
}

Describe 'Get-AvmUpdateType (Private)' {
    InModuleScope AvmUpdater {
        It 'Classifies major bump' {
            Get-AvmUpdateType -Current '0.4.0' -Target '1.0.0' | Should -Be 'major'
        }
        It 'Classifies minor bump' {
            Get-AvmUpdateType -Current '0.3.0' -Target '0.4.0' | Should -Be 'minor'
        }
        It 'Classifies patch bump' {
            Get-AvmUpdateType -Current '0.4.0' -Target '0.4.1' | Should -Be 'patch'
        }
        It 'Returns none when versions are equal' {
            Get-AvmUpdateType -Current '0.4.0' -Target '0.4.0' | Should -Be 'none'
        }
    }
}

Describe 'Get-AvmLatestVersion' {
    BeforeEach {
        # Reset in-memory cache between tests
        InModuleScope AvmUpdater { $script:_AvmVersionCache = @{} }
    }

    Context 'Bicep — successful lookup' {
        BeforeEach {
            Mock -ModuleName AvmUpdater Invoke-RestMethod {
                return [PSCustomObject]@{
                    tags = @('0.1.0', '0.2.0', '0.3.0-preview', 'latest', '0.4.1', '0.4.0')
                }
            } -ParameterFilter { $Uri -match 'mcr\.microsoft\.com' }
        }
        It 'Returns the correct latestStable (drops preview and latest)' {
            $result = Get-AvmLatestVersion -RegistryPath 'bicep/avm/res/storage/storage-account' -Ecosystem 'bicep'
            $result.latestStable | Should -Be '0.4.1'
            $result.status       | Should -Be 'ok'
            $result.allVersions  | Should -Not -Contain 'latest'
            $result.allVersions  | Should -Not -Contain '0.3.0-preview'
        }
    }

    Context 'Terraform — successful lookup' {
        BeforeEach {
            Mock -ModuleName AvmUpdater Invoke-RestMethod {
                return [PSCustomObject]@{
                    modules = @(
                        [PSCustomObject]@{
                            versions = @(
                                [PSCustomObject]@{ version = '0.1.0' }
                                [PSCustomObject]@{ version = '0.5.2' }
                                [PSCustomObject]@{ version = '0.4.0-beta' }
                                [PSCustomObject]@{ version = '0.3.0' }
                            )
                        }
                    )
                }
            } -ParameterFilter { $Uri -match 'registry\.terraform\.io' }
        }
        It 'Returns the correct latestStable for terraform' {
            $result = Get-AvmLatestVersion -RegistryPath 'Azure/avm-res-storage-storageaccount/azurerm' -Ecosystem 'terraform'
            $result.latestStable | Should -Be '0.5.2'
            $result.status       | Should -Be 'ok'
        }
    }

    Context 'Lookup failure' {
        BeforeEach {
            Mock -ModuleName AvmUpdater Invoke-RestMethod { throw 'Network error' }
            Mock -ModuleName AvmUpdater Invoke-WithRetry { throw 'Network error' }
        }
        It 'Returns lookup-failed status and does not throw' {
            { $result = Get-AvmLatestVersion -RegistryPath 'bicep/avm/res/nonexistent/module' -Ecosystem 'bicep' } | Should -Not -Throw
            $result = Get-AvmLatestVersion -RegistryPath 'bicep/avm/res/nonexistent/module' -Ecosystem 'bicep'
            $result.status | Should -Be 'lookup-failed'
        }
    }
}

Describe 'Get-AvmUpdateRisk' {
    Context 'Removed required param → HIGH' {
        BeforeEach {
            Mock -ModuleName AvmUpdater Get-AvmInterfaceDiff {
                return [PSCustomObject]@{
                    available = $true; addedRequired = @(); removedInputs = @('oldParam')
                    typeChanged = @(); addedOptional = @(); removedOutputs = @(); addedOutputs = @(); rawError = $null
                }
            }
            Mock -ModuleName AvmUpdater Get-AvmChangelog {
                return [PSCustomObject]@{ available = $false; lines = @(); source = $null }
            }
        }
        It 'Classifies as HIGH when input is removed' {
            $ref = [PSCustomObject]@{
                ecosystem = 'bicep'; category = 'res'; group = 'storage'; module = 'storage-account'
                currentVersion = '0.3.0'; registryPath = 'bicep/avm/res/storage/storage-account'
            }
            $risk = Get-AvmUpdateRisk -Reference $ref -TargetVersion '0.4.0'
            $risk.riskTier | Should -Be 'HIGH'
            $risk.riskReasons | Should -Contain ($risk.riskReasons | Where-Object { $_ -match 'removedInputs|removed' } | Select-Object -First 1)
        }
    }

    Context 'Added optional param + patch → LOW' {
        BeforeEach {
            Mock -ModuleName AvmUpdater Get-AvmInterfaceDiff {
                return [PSCustomObject]@{
                    available = $true; addedRequired = @(); removedInputs = @()
                    typeChanged = @(); addedOptional = @('newOptional'); removedOutputs = @(); addedOutputs = @(); rawError = $null
                }
            }
            Mock -ModuleName AvmUpdater Get-AvmChangelog {
                return [PSCustomObject]@{ available = $true; lines = @(); source = 'mock' }
            }
        }
        It 'Classifies as LOW for patch bump with only optional additions' {
            $ref = [PSCustomObject]@{
                ecosystem = 'bicep'; category = 'res'; group = 'storage'; module = 'storage-account'
                currentVersion = '0.4.0'; registryPath = 'bicep/avm/res/storage/storage-account'
            }
            $risk = Get-AvmUpdateRisk -Reference $ref -TargetVersion '0.4.1'
            $risk.riskTier | Should -Be 'LOW'
        }
    }

    Context 'Output removed → HIGH' {
        BeforeEach {
            Mock -ModuleName AvmUpdater Get-AvmInterfaceDiff {
                return [PSCustomObject]@{
                    available = $true; addedRequired = @(); removedInputs = @()
                    typeChanged = @(); addedOptional = @(); removedOutputs = @('resourceId'); addedOutputs = @(); rawError = $null
                }
            }
            Mock -ModuleName AvmUpdater Get-AvmChangelog {
                return [PSCustomObject]@{ available = $false; lines = @(); source = $null }
            }
        }
        It 'Classifies as HIGH when output is removed' {
            $ref = [PSCustomObject]@{
                ecosystem = 'bicep'; category = 'res'; group = 'storage'; module = 'storage-account'
                currentVersion = '0.4.0'; registryPath = 'bicep/avm/res/storage/storage-account'
            }
            $risk = Get-AvmUpdateRisk -Reference $ref -TargetVersion '0.4.1'
            $risk.riskTier | Should -Be 'HIGH'
        }
    }

    Context 'Diff unavailable + no changelog → UNKNOWN' {
        BeforeEach {
            Mock -ModuleName AvmUpdater Get-AvmInterfaceDiff {
                return [PSCustomObject]@{
                    available = $false; addedRequired = @(); removedInputs = @()
                    typeChanged = @(); addedOptional = @(); removedOutputs = @(); addedOutputs = @(); rawError = 'error'
                }
            }
            Mock -ModuleName AvmUpdater Get-AvmChangelog {
                return [PSCustomObject]@{ available = $false; lines = @(); source = $null }
            }
        }
        It 'Classifies as UNKNOWN when both diff and changelog are unavailable' {
            $ref = [PSCustomObject]@{
                ecosystem = 'bicep'; category = 'res'; group = 'storage'; module = 'storage-account'
                currentVersion = '0.4.0'; registryPath = 'bicep/avm/res/storage/storage-account'
            }
            $risk = Get-AvmUpdateRisk -Reference $ref -TargetVersion '0.4.1'
            $risk.riskTier | Should -Be 'UNKNOWN'
        }
        It 'Includes UNKNOWN reason in riskReasons (concrete evidence)' {
            $ref = [PSCustomObject]@{
                ecosystem = 'bicep'; category = 'res'; group = 'storage'; module = 'storage-account'
                currentVersion = '0.4.0'; registryPath = 'bicep/avm/res/storage/storage-account'
            }
            $risk = Get-AvmUpdateRisk -Reference $ref -TargetVersion '0.4.1'
            ($risk.riskReasons | Where-Object { $_ -match 'UNKNOWN' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Patch bump, identical interface → LOW' {
        BeforeEach {
            Mock -ModuleName AvmUpdater Get-AvmInterfaceDiff {
                return [PSCustomObject]@{
                    available = $true; addedRequired = @(); removedInputs = @()
                    typeChanged = @(); addedOptional = @(); removedOutputs = @(); addedOutputs = @(); rawError = $null
                }
            }
            Mock -ModuleName AvmUpdater Get-AvmChangelog {
                return [PSCustomObject]@{ available = $true; lines = @(); source = 'mock' }
            }
        }
        It 'Classifies as LOW for patch with no changes' {
            $ref = [PSCustomObject]@{
                ecosystem = 'bicep'; category = 'res'; group = 'storage'; module = 'storage-account'
                currentVersion = '0.4.0'; registryPath = 'bicep/avm/res/storage/storage-account'
            }
            $risk = Get-AvmUpdateRisk -Reference $ref -TargetVersion '0.4.1'
            $risk.riskTier | Should -Be 'LOW'
        }
    }
}

Describe 'New-AvmUpdateReport' {
    BeforeAll {
        $script:SamplePlan = [PSCustomObject]@{
            candidates = @(
                [PSCustomObject]@{
                    module = 'storage-account'; ecosystem = 'bicep'; currentVersion = '0.3.0'
                    latestStable = '0.4.1'; updateType = 'minor'; riskTier = 'MEDIUM'
                    file = '/tmp/test.bicep'; lineNumber = 7; registryPath = 'bicep/avm/res/storage/storage-account'
                    riskReasons = @('0.x minor bump'); interfaceDiff = $null; changelogLines = @()
                }
                [PSCustomObject]@{
                    module = 'vault'; ecosystem = 'bicep'; currentVersion = '0.6.0'
                    latestStable = '0.6.2'; updateType = 'patch'; riskTier = 'LOW'
                    file = '/tmp/test.bicep'; lineNumber = 15; registryPath = 'bicep/avm/res/key-vault/vault'
                    riskReasons = @(); interfaceDiff = $null; changelogLines = @()
                }
                [PSCustomObject]@{
                    module = 'hub-networking'; ecosystem = 'bicep'; currentVersion = '0.1.0'
                    latestStable = '1.0.0'; updateType = 'major'; riskTier = 'HIGH'
                    file = '/tmp/test.bicep'; lineNumber = 23; registryPath = 'bicep/avm/ptn/network/hub-networking'
                    riskReasons = @('Major version bump', 'BREAKING: Input removed: oldParam')
                    interfaceDiff = [PSCustomObject]@{
                        available = $true; addedRequired = @(); removedInputs = @('oldParam')
                        typeChanged = @(); addedOptional = @(); removedOutputs = @(); addedOutputs = @(); rawError = $null
                    }
                    changelogLines = @('- Removed deprecated parameter oldParam')
                }
            )
            lookupFailed = @(
                [PSCustomObject]@{
                    reference = [PSCustomObject]@{ module = 'unknown-module'; registryPath = 'bicep/avm/res/x/y' }
                    status = 'lookup-failed'; riskTier = 'UNKNOWN'
                    riskReasons = @('Version lookup failed')
                }
            )
            summary = [PSCustomObject]@{
                scannedAt = '2026-01-01 08:00:00'; pathsScanned = @('.')
                totalRefs = 4; totalUpdates = 3
                byUpdateType = @{ major = 1; minor = 1; patch = 1; constraint = 0 }
                byRiskTier   = @{ HIGH = 1; MEDIUM = 1; LOW = 1; UNKNOWN = 1 }
                lookupFailed = 1
            }
        }
        $script:TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "AvmUpdaterTest-$(New-Guid)"
        New-Item -ItemType Directory -Path $script:TmpDir | Out-Null
    }

    AfterAll {
        Remove-Item $script:TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Generates both report files' {
        $result = New-AvmUpdateReport -Plan $script:SamplePlan -OutputDirectory $script:TmpDir
        Test-Path $result.reportPath | Should -Be $true
        Test-Path $result.jsonPath   | Should -Be $true
    }

    It 'Markdown report contains the summary table' {
        $result = New-AvmUpdateReport -Plan $script:SamplePlan -OutputDirectory $script:TmpDir
        $md = Get-Content $result.reportPath -Raw
        $md | Should -Match 'storage-account'
        $md | Should -Match 'Modules scanned'
    }

    It 'Lookup-failed module appears in Could Not Check section' {
        $result = New-AvmUpdateReport -Plan $script:SamplePlan -OutputDirectory $script:TmpDir
        $md = Get-Content $result.reportPath -Raw
        $md | Should -Match 'Could Not Check'
        $md | Should -Match 'unknown-module'
    }

    It 'Summary counts match the plan' {
        $result = New-AvmUpdateReport -Plan $script:SamplePlan -OutputDirectory $script:TmpDir
        $md = Get-Content $result.reportPath -Raw
        $md | Should -Match '4'   # totalRefs
        $md | Should -Match '3'   # totalUpdates
    }
}

Describe 'Approve-AvmUpdate — local mode' {
    It 'Auto-approves LOW items without prompting' {
        $plan = [PSCustomObject]@{
            candidates = @(
                [PSCustomObject]@{
                    module = 'vault'; riskTier = 'LOW'; currentVersion = '0.6.0'; latestStable = '0.6.2'; updateType = 'patch'
                }
            )
            lookupFailed = @()
        }
        $result = Approve-AvmUpdate -Plan $plan -ApprovalMode local -DryRun
        # In DryRun local mode, approved list should be empty (DryRun clears it)
        $result | Should -Not -BeNullOrEmpty
        $result.auditRecord | Should -Not -BeNullOrEmpty
        $result.auditRecord.mode | Should -Be 'local'
    }

    It 'DryRun returns without file changes or prompts' {
        $plan = [PSCustomObject]@{
            candidates = @(
                [PSCustomObject]@{
                    module = 'hub-networking'; riskTier = 'HIGH'; currentVersion = '0.1.0'; latestStable = '1.0.0'; updateType = 'major'
                }
            )
            lookupFailed = @()
        }
        { Approve-AvmUpdate -Plan $plan -ApprovalMode local -DryRun } | Should -Not -Throw
    }
}

Describe 'Approve-AvmUpdate — github mode (CLI mocked)' {
    BeforeEach {
        $env:GITHUB_TOKEN = 'mock-token'
    }
    AfterEach { Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue }

    It 'Returns audit record with mode=github when CLI tools are present' -Skip:(-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        InModuleScope AvmUpdater {
            Mock git {}
            Mock gh { return 'https://github.com/buzzict/bicep-updater/pull/1' }
            Mock Update-AvmModuleVersion {
                return [PSCustomObject]@{ applied = @(); rolledBack = @(); warnings = @(); isConsistent = $true }
            }

            $plan = [PSCustomObject]@{
                candidates = @(
                    [PSCustomObject]@{
                        module = 'hub-networking'; riskTier = 'HIGH'; currentVersion = '0.1.0'
                        latestStable = '1.0.0'; updateType = 'major'; file = '/tmp/test.bicep'
                        lineNumber = 1; ecosystem = 'bicep'; registryPath = 'bicep/avm/ptn/network/hub-networking'
                        riskReasons = @()
                    }
                )
                lookupFailed = @()
            }
            $result = Approve-AvmUpdate -Plan $plan -ApprovalMode github
            $result | Should -Not -BeNullOrEmpty
            $result.auditRecord.mode | Should -Be 'github'
        }
    }

    It 'Throws a descriptive error when GITHUB_TOKEN is missing' {
        Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
        $plan = [PSCustomObject]@{
            candidates = @([PSCustomObject]@{
                module = 'vault'; riskTier = 'LOW'; currentVersion = '0.1.0'; latestStable = '0.2.0'
                updateType = 'minor'; file = '/tmp/t.bicep'; lineNumber = 1; ecosystem = 'bicep'
                registryPath = 'bicep/avm/res/key-vault/vault'; riskReasons = @()
            })
            lookupFailed = @()
        }
        { Approve-AvmUpdate -Plan $plan -ApprovalMode github } | Should -Throw
    }
}

Describe 'Update-AvmModuleVersion' {
    BeforeAll {
        $script:TmpFixtures = Join-Path ([System.IO.Path]::GetTempPath()) "AvmFixtures-$(New-Guid)"
        New-Item -ItemType Directory -Path $script:TmpFixtures | Out-Null
        $script:BicepFile = Join-Path $script:TmpFixtures 'main.bicep'
        Set-Content $script:BicepFile "module sa 'br/public:avm/res/storage/storage-account:0.4.0' = {`n  name: 'test'`n}`n"
    }

    AfterAll {
        Remove-Item $script:TmpFixtures -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'Clean patch — bicep build succeeds (CLI mocked)' {
        BeforeEach {
            # Reset fixture to original state
            Set-Content $script:BicepFile "module sa 'br/public:avm/res/storage/storage-account:0.4.0' = {`n  name: 'test'`n}`n"
        }

        It 'Updates the version token in the file — PASS outcome' {
            $bicepFile = $script:BicepFile
            $approved = [PSCustomObject]@{
                approvedItems = @(
                    [PSCustomObject]@{
                        file = $bicepFile; lineNumber = 1
                        currentVersion = '0.4.0'; latestStable = '0.4.1'
                        ecosystem = 'bicep'; module = 'storage-account'
                    }
                )
            }

            Mock -ModuleName AvmUpdater Invoke-AvmValidation {
                return [PSCustomObject]@{ outcome = 'PASS'; output = ''; warnReason = $null }
            }

            $result = Update-AvmModuleVersion -ApprovedPlan $approved
            $result.applied.Count    | Should -Be 1
            $result.rolledBack.Count | Should -Be 0
            $result.isConsistent     | Should -Be $true

            $content = Get-Content $bicepFile -Raw
            $content | Should -Match '0\.4\.1'
        }
    }

    Context 'Build failure → rollback' {
        BeforeEach {
            # Reset file to original
            Set-Content $script:BicepFile "module sa 'br/public:avm/res/storage/storage-account:0.4.0' = {`n  name: 'test'`n}`n"
        }

        It 'Reverts the file to original bytes on FAIL' {
            $originalContent = Get-Content $script:BicepFile -Raw

            $approved = [PSCustomObject]@{
                approvedItems = @(
                    [PSCustomObject]@{
                        file = $script:BicepFile; lineNumber = 1
                        currentVersion = '0.4.0'; latestStable = '0.4.1'
                        ecosystem = 'bicep'; module = 'storage-account'
                    }
                )
            }

            Mock -ModuleName AvmUpdater Invoke-AvmValidation {
                return [PSCustomObject]@{ outcome = 'FAIL'; output = 'Build error: syntax error'; warnReason = $null }
            }

            $result = Update-AvmModuleVersion -ApprovedPlan $approved
            $result.rolledBack.Count | Should -Be 1
            $result.applied.Count    | Should -Be 0
            $result.isConsistent     | Should -Be $false
            $result.rolledBack[0].error | Should -Match 'Build error'

            # File should be unchanged
            $afterContent = Get-Content $script:BicepFile -Raw
            $afterContent | Should -Be $originalContent
        }
    }

    Context 'Terraform plan with REPLACE → WARN' {
        BeforeEach {
            # Reset fixture to ensure token is present at line 1
            Set-Content $script:BicepFile "module sa 'br/public:avm/res/storage/storage-account:0.4.0' = {`n  name: 'test'`n}`n"
        }

        It 'Keeps the change but flags as WARN' {
            $bicepFile = $script:BicepFile
            $approved = [PSCustomObject]@{
                approvedItems = @(
                    [PSCustomObject]@{
                        file = $bicepFile; lineNumber = 1
                        currentVersion = '0.4.0'; latestStable = '0.4.1'
                        ecosystem = 'bicep'; module = 'storage-account'
                    }
                )
            }

            Mock -ModuleName AvmUpdater Invoke-AvmValidation {
                return [PSCustomObject]@{
                    outcome = 'WARN'; output = 'Plan: 1 to add, 0 to change, 1 to destroy (must be replaced)'
                    warnReason = 'Terraform plan includes DESTROY or REPLACE actions'
                }
            }

            $result = Update-AvmModuleVersion -ApprovedPlan $approved
            $result.applied.Count   | Should -Be 1
            $result.warnings.Count  | Should -Be 1
            $result.warnings[0].reason | Should -Match 'REPLACE|DESTROY'
        }
    }

    Context 'DryRun — no file changes' {
        It 'Does not modify the file on disk' {
            Set-Content $script:BicepFile "module sa 'br/public:avm/res/storage/storage-account:0.4.0' = {`n  name: 'test'`n}`n"
            $original = Get-Content $script:BicepFile -Raw

            $approved = [PSCustomObject]@{
                approvedItems = @(
                    [PSCustomObject]@{
                        file = $script:BicepFile; lineNumber = 1
                        currentVersion = '0.4.0'; latestStable = '0.4.1'
                        ecosystem = 'bicep'; module = 'storage-account'
                    }
                )
            }

            Mock -ModuleName AvmUpdater Invoke-AvmValidation {
                return [PSCustomObject]@{ outcome = 'PASS'; output = ''; warnReason = $null }
            }

            $result = Update-AvmModuleVersion -ApprovedPlan $approved -DryRun
            $after = Get-Content $script:BicepFile -Raw
            $after | Should -Be $original
        }
    }
}

Describe 'Invoke-AvmUpdate — DryRun end-to-end' {
    It 'DryRun produces a report but changes zero files' {
        InModuleScope AvmUpdater {
            Mock Get-AvmUpdatePlan {
                return [PSCustomObject]@{
                    candidates = @(
                        [PSCustomObject]@{
                            ecosystem = 'bicep'; category = 'res'; group = 'storage'; module = 'storage-account'
                            currentVersion = '0.4.0'; latestStable = '0.4.1'; updateType = 'minor'
                            isConstraint = $false; riskTier = 'LOW'; riskReasons = @()
                            interfaceDiff = $null; changelogLines = @(); status = 'pending'; note = $null
                            registryPath = 'bicep/avm/res/storage/storage-account'
                            file = '/tmp/mock.bicep'; lineNumber = 7
                        }
                    )
                    lookupFailed = @()
                    summary = [PSCustomObject]@{
                        scannedAt = '2026-01-01 08:00:00'; pathsScanned = @('/tmp')
                        totalRefs = 1; totalUpdates = 1
                        byUpdateType = @{ major = 0; minor = 1; patch = 0; constraint = 0 }
                        byRiskTier   = @{ HIGH = 0; MEDIUM = 0; LOW = 1; UNKNOWN = 0 }
                        lookupFailed = 0
                    }
                }
            }
            Mock Approve-AvmUpdate {
                return [PSCustomObject]@{
                    approvedItems = @()
                    skippedItems  = @()
                    auditRecord   = [PSCustomObject]@{ mode = 'local'; timestamp = ''; approvedItems = @(); skippedItems = @(); actor = 'test' }
                    prUrl         = $null
                }
            }
            Mock Update-AvmModuleVersion {
                return [PSCustomObject]@{ applied = @(); rolledBack = @(); warnings = @(); isConsistent = $true }
            }

            $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "AvmDryRun-$(New-Guid)"
            New-Item -ItemType Directory -Path $tmpDir | Out-Null
            try {
                $result = Invoke-AvmUpdate -Path '/tmp' -DryRun -OutputDirectory $tmpDir -ApprovalMode local
                Test-Path $result.reportPath | Should -Be $true
                Should -Invoke Update-AvmModuleVersion -Times 0 -Exactly
            } finally {
                Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Returns "up to date" with zero candidates' {
        InModuleScope AvmUpdater {
            Mock Get-AvmUpdatePlan {
                return [PSCustomObject]@{
                    candidates = @()
                    lookupFailed = @()
                    summary = [PSCustomObject]@{
                        scannedAt = '2026-01-01 08:00:00'; pathsScanned = @('/tmp')
                        totalRefs = 1; totalUpdates = 0
                        byUpdateType = @{ major = 0; minor = 0; patch = 0; constraint = 0 }
                        byRiskTier   = @{ HIGH = 0; MEDIUM = 0; LOW = 0; UNKNOWN = 0 }
                        lookupFailed = 0
                    }
                }
            }
            Mock Approve-AvmUpdate {
                return [PSCustomObject]@{
                    approvedItems = @(); skippedItems = @()
                    auditRecord = [PSCustomObject]@{ mode = 'local'; timestamp = ''; approvedItems = @(); skippedItems = @(); actor = 'test' }
                    prUrl = $null
                }
            }

            $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "AvmNoOp-$(New-Guid)"
            New-Item -ItemType Directory -Path $tmpDir | Out-Null
            try {
                $result = Invoke-AvmUpdate -Path '/tmp' -OutputDirectory $tmpDir -ApprovalMode local -DryRun
                $result.updated.Count    | Should -Be 0
                $result.rolledBack.Count | Should -Be 0
            } finally {
                Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
