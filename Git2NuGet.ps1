# variables init
$repoURI = "https://github.com/kontur-exploitation/testcase-posharp.git"
$repoFolder = $repoURI.Substring($repoURI.LastIndexOf("/")+1,$repoURI.LastIndexOf(".")-$repoURI.LastIndexOf("/")-1) # testcase-posharp
$repoRoot = "D:\Test" # root folder of repos
$checkPeriod = 10 # seconds
$msbuildLocation = "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe"
$appExe = $repoRoot + "\" + $repoFolder + "\bin\Debug\CSharpProject.exe"
$nugetPath = "D:\Test\nuget.exe"
$xmlTemplatePath = $PSCommandPath.Substring(0, $PSCommandPath.LastIndexOf(".")) + ".xml"

$PSCommandPath
$xmlTemplatePath

# Needed for redirecting stdout properly
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

# Creating $repoRoot if needed
if(!(Test-Path -Path $repoRoot)){
    New-Item -ItemType directory -Path $repoRoot
}
Set-Location $repoRoot

# Cloning repository if needed
if(!(Test-Path -Path “$repoRoot\$repoFolder”)){
    Write-Host(“Cloning $repoUri into $repoRoot\$repoFolder”)
    git clone $repoURI $repoFolder 2>&1 | Write-Host
}
else {
    Set-Location $repoFolder
}

Write-Host("Pulling remote repository every $checkPeriod seconds. Press Ctrl-C to stop the process.")

# Main loop
while ($true) {
    Start-Sleep -Seconds $checkPeriod
    $repoStatus = git pull
    $currentDate = Get-Date
    if ($repoStatus -eq "Already up to date.") {
        Write-Host ("$currentDate - $repoStatus")
        } 
    else {
        Write-Host ("$currentDate - Changes detected, building an app and a NuGet packet.")
        $processInfo = Start-Process -FilePath $msbuildLocation -ArgumentList "/t:Clean,Build" -NoNewWindow -Wait -PassThru
        $appOutput = Execute-Command -commandPath $appExe -commandTitle $appExe -commandArguments ""
        $appOutput.stdout
        
        
    }

}

