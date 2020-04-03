# Test task for Kontur

# requires -version 5

# ======= Variables init / Import settings ========

# Import settings from config file Git2Nuget.cfg
$xmlConfigFile = $PSCommandPath.Substring(0, $PSCommandPath.LastIndexOf(".")) + ".cfg"
[xml]$ConfigFile = Get-Content $xmlConfigFile

$repoURI = $ConfigFile.Settings.repoURI
$repoFolder = $repoURI.Substring($repoURI.LastIndexOf("/")+1,$repoURI.LastIndexOf(".")-$repoURI.LastIndexOf("/")-1) # testcase-posharp
$repoRoot = $ConfigFile.Settings.repoRoot # root folder of repos
$repoNuget = $repoRoot + "\" + $repoFolder # .nuspec file location folder

$checkPeriod = $ConfigFile.Settings.checkPeriod # seconds
$msbuildLocation = $ConfigFile.Settings.msbuildLocation
$appExe = $repoRoot + "\" + $repoFolder + $ConfigFile.Settings.appExe
$nugetPath = $ConfigFile.Settings.nugetPath 
$nugetAPIKey = $ConfigFile.Settings.nugetAPIKey

# email settings
$from = $ConfigFile.Settings.emailSettings.From
$to = $ConfigFile.Settings.emailSettings.To
$SMTPServer = $ConfigFile.Settings.emailSettings.SMTPServer
$SMTPPort = $ConfigFile.Settings.emailSettings.SMTPPort

$emailPassword =  ConvertTo-SecureString -String $ConfigFile.Settings.emailSettings.emailPassword -AsPlainText -Force # not secure, but it's nature of PS

# nuspec template
$xmlTemplatePath = $PSCommandPath.Substring(0, $PSCommandPath.LastIndexOf(".")) + ".nuspec"
[xml]$xmlTemplate = Get-Content $xmlTemplatePath -Encoding UTF8
$Timer = [System.Diagnostics.Stopwatch]::StartNew() # needed to substract script running time from $checkPeriod
$Timer.Stop()

# ======= Functions ========

# Needed for redirect stdout properly
function Execute-Command ($commandTitle, $commandPath, $commandArguments)
{
  Try {
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $commandPath
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = $commandArguments
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    [pscustomobject]@{
        commandTitle = $commandTitle
        stdout = $p.StandardOutput.ReadToEnd()
        stderr = $p.StandardError.ReadToEnd()
        ExitCode = $p.ExitCode
    }
    $p.WaitForExit()
  }
  Catch {
     exit
  }
}


# Emailing subroutine
function Send-ErrorMail ($Subject, $Body)
{
    
$emailCredentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $from, $emailPassword

Send-MailMessage -BodyAsHtml -From $From -to $To -Subject "$Subject" -Body "<h2><font color='red'>$Body</font></h2>" -SmtpServer $SMTPServer -Port $SMTPPort -UseSsl -Credential $emailCredentials

}

# ======= Init ========

# Creating $repoRoot folder if needed
if(!(Test-Path -Path $repoRoot)){
    New-Item -ItemType directory -Path $repoRoot
}

Set-Location $repoRoot

# Cloning repository if needed
if(!(Test-Path -Path “$repoRoot\$repoFolder”)){
    Write-Host(“Cloning $repoUri into $repoRoot\$repoFolder”)
    $gitClone = git clone $repoURI $repoFolder 2>&1 # 2>&1 - some magic to avoid errors as git uses stderr instead of stdout
    if ($LASTEXITCODE -ne 0) {
        Write-Host -ForegroundColor Red "Error cloning repository"
        Write-Host -ForegroundColor DarkRed $gitClone
        exit $LASTEXITCODE
    }
}

Set-Location $repoFolder
Write-Host("Pulling remote repository every $checkPeriod seconds. Press Ctrl-C to stop the process.")


# ======= Main loop ========

while ($true) {
    $Timer.Reset()
    $Timer.Start() 
    $currentDate = Get-Date
    $repoStatus = git pull 2>&1
    if ($repoStatus -ne "Already up to date.") { # repo updated
        
        Write-Host -ForegroundColor Green ("$currentDate - Changes detected, processing...")
        $msbuildProcess = Start-Process -FilePath $msbuildLocation -ArgumentList "/t:Clean,Build" -NoNewWindow -PassThru -RedirectStandardOutput ..\stdout.txt -RedirectStandardError ..\stderr.txt # Debug
        $msbuildProcess.WaitForExit() # workarond for a bug in PS (infitite wait with -Wait option)
        if ($LASTEXITCODE -eq 0) { # no build errors
            Write-Host -ForegroundColor Gray  ("   MSBuild: done")
            $appOutput = Execute-Command -commandPath $appExe -commandTitle $appExe -commandArguments ""
            Write-Host -ForegroundColor Gray  ("  Test run: done")

            # creating new xml file
            $xmlTemplate.package.metadata.version = (Get-Item $appExe).VersionInfo.FileVersion
            $xmlTemplate.package.metadata.description = $appOutput.stdout
            
            $repoAuthor = git log -1 --pretty=format:'%an' # get an author of the last commit
            $xmlTemplate.package.metadata.authors = $repoAuthor.ToString()
            
            $nugetXmlFile = $repoNuget + "\" + $xmlTemplate.package.metadata.id + ".nuspec"
            $xmlTemplate.Save($nugetXmlFile)
            Write-Host -ForegroundColor Gray ("   .nuspec: done")
            
            $nugetProcess = Start-Process -FilePath $nugetPath -ArgumentList "pack $nugetXmlFile" -NoNewWindow -Wait -PassThru
            if ($nugetProcess.ExitCode -eq 0) { # no packing errors
                    Write-Host -ForegroundColor Gray ("NuGet pack: done")

                    $nupkgFile = Get-ChildItem -File -Name *.nupkg

                    if ($nupkgFile -ne $null) {  # looking for .nupkg file
                        $nugetProcessPush = Start-Process -FilePath $nugetPath -ArgumentList "push $nupkgFile -Source https://api.nuget.org/v3/index.json -ApiKey $nugetAPIKey" -NoNewWindow -Wait -PassThru -RedirectStandardOutput ..\stdout.txt -RedirectStandardError ..\stderr.txt # Debug
                        if ($nugetProcessPush.ExitCode -eq 0) { # no pushing errors
                                Write-Host -ForegroundColor Gray ("NuGet push: done")
                                Remove-Item -Path *.nupkg # cleaning up
                                Write-Host -ForegroundColor Green ("Processing done. Waiting for the next update...")
                        } else {
                                Write-Host -ForegroundColor Red "NuGet failed to push the project, email sent..."
                                Send-ErrorMail -Subject "Git2NuGet: NuGet failed to push the project" -Body "NuGet failed to push the project."

                        }

                     } else {
                            Write-Host -ForegroundColor Red "NuGet failed to pack the project, email sent..."
                            Send-ErrorMail -Subject "Git2NuGet Error: NuGet failed to pack the project" -Body "NuGet failed to pack the project."
                     }

            } else {
                Write-Host -ForegroundColor Red "NuGet failed to pack the project, email sent..."
                Send-ErrorMail -Subject "Git2NuGet Error: NuGet failed to pack the project" -Body "NuGet failed to pack the project.>"
            }
                        
        } else {
            Write-Host -ForegroundColor Red "MSBuild failed to build the project, email sent..."
            Send-ErrorMail -Subject "Git2NuGet Error: MSBuild failed to build the project" -Body "MSBuild failed to build the project."
        }
        
    } else {
        if ($LASTEXITCODE -eq 0) { # no changes in the repository
            Write-Host ("$currentDate - $repoStatus") 
        } else { # Houston, we have a problem - git pull error
            Write-Host -ForegroundColor Red "Git failed to pull the project, email sent..."
            Send-ErrorMail -Subject "Git2NuGet Error: Git failed to pull the project" -Body "Git failed to pull the project."
        }
    }
    $Timer.Stop()
    $checkPeriodCorrected = $checkPeriod - $Timer.Elapsed.Seconds # taking to consideration script run time
    Start-Sleep -Seconds $checkPeriodCorrected
   
}

