# SSH autopush helper for vnikolas2009/iGram.
#
# Pushes the current branch to origin over SSH. With -Commit it first stages and
# commits every change; without it, existing commits are only pushed.
#
# Usage:
#   .\autopush.ps1                 # push the current branch
#   .\autopush.ps1 -Commit         # commit all changes, then push
#   .\autopush.ps1 -Commit -Message "feat: ..." -Branch tweaks/custom-swiftgram
#
# The repository remote is git@github.com:vnikolas2009/iGram.git and git uses
# core.sshCommand with ~/.ssh/id_ed25519, so no password or token is needed.

param(
    [switch]$Commit,
    [string]$Message = "",
    [string]$Branch = ""
)

$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot

if (-not $Branch) {
    $Branch = (& git branch --show-current).Trim()
}
if ([string]::IsNullOrWhiteSpace($Branch)) {
    throw "Detached HEAD: checkout a branch first."
}

if ($Commit) {
    & git add -A
    $status = & git status --porcelain
    if ($status) {
        if ([string]::IsNullOrWhiteSpace($Message)) {
            $Message = "chore: auto update " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        }
        & git commit -m $Message
        if ($LASTEXITCODE -ne 0) {
            throw "git commit failed with exit code $LASTEXITCODE"
        }
    } else {
        Write-Host "No changes to commit."
    }
}

& git push origin $Branch
if ($LASTEXITCODE -ne 0) {
    throw "git push failed with exit code $LASTEXITCODE"
}

Write-Host "Pushed $Branch to git@github.com:vnikolas2009/iGram.git."
