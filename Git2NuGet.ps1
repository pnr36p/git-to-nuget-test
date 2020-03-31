$repoURI = "https://github.com/kontur-exploitation/testcase-posharp.git"
$repoFolder = $repoURI.Substring($repoURI.LastIndexOf("/")+1,$repoURI.LastIndexOf(".")-$repoURI.LastIndexOf("/")-1)
$checkoutPath = "D:\Test"
$checkPeriod = 30 # seconds

if(!(Test-Path -Path $checkoutPath)){
    New-Item -ItemType directory -Path $checkoutPath
}
Set-Location $checkoutPath

if(!(Test-Path -Path “$checkoutPath\$repoFolder”)){
    Write-Host(“Cloning $repoUri into $checkoutPath\$repoFolder”)
    git clone $repoURI $repoFolder 2>&1 | Write-Host
}
else {
    Set-Location $repoFolder
}

git for-each-ref --format='%(refname:short)' refs/remotes/origin | Write-Host


