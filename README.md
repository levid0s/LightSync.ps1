## LightSync.sh

LightSync is a utility that lets you define various Windows config parameters as yaml files, and apply those configs.

It can install itself as a Scheduled Task and run periodically.

I'm using this script, combined with Dropbox, to sync my portable apps and configs across multiple machines.

This tool builds on the fuctions I published in the [useful/PS-Winhelpers](https://github.com/levid0s/useful/tree/master/ps-winhelpers) repo.

When syncing my portable apps, the 'LSH Apps' Start Menu folder gets created.

The shortcuts have a ⚡ suffix so I know they are the portable versions.

![Start Menu](./res/demo-folder.png)



### Supported config types

- `reg`: Windows Registry
- `assocs.assoc`: File Associations
- `assocs.verb`: File Associations - Custom verb
- `shortcuts`: Start Menu Shortcuts
- `runonce`: RunOnce commands
- `junction`: Junctions
- `symlink`: Symlinks
- `paths`: User %PATH% entries
- `dropboxignore`: Adding certain folders to Dropbox Ignore List
- `dropboxoffline`: Setting certain folders to be downloaded by Dropbox
- `folders.versionfrom`: Setting a folder comment to match a binary's version entry
- `files.state=absent`: Deleting certain files


### Usage

#### Step 1: Have some yaml files in ./packages

For example, if you want to sync 7-zip portable, there's a `7-zip.yaml` file already in the `./packages` folder.

```yaml
---
assocs:
  - AssocIcon: '{PkgPath}/7z.dll,1'
    assoc: ["7z", "gz", "rar", "tar", "tgz", "zip"]
    target: '{PkgPath}/7zFM.exe'
    friendlyAppName: '{PkgName} ⚡'
folders:
  - path: '{PkgPath}'
    versionfrom: '{PkgPath}/7zFM.exe'
shortcuts:
  - assocIcon: '{PkgPath}/7z.dll,1'
    icon: '{PkgPath}/7zFM.exe'
    name: '{PkgName}'
    params: ''
    target: '{PkgPath}/7zFM.exe'
dropboxoffline:
  - path: '{PkgPath}'
    mode: 'Offline'
```

The script will replace the `{PkgPath}` and `{PkgName}` variables with the actual values.

- `{LSHRoot}` is the "LightSync Root" configured during the Install step
- `{PkgName}` is the name of the yaml file without the extension. So, for `7-zip.yaml`, the `{PkgName}` is `7-zip`
- `{PkgPath}` is `{LSHRoot}/{PkgName}`


Dowload the portable version of [7-zip](https://www.7-zip.org/a/7z2300-extra.7z) and extract it to the "{LSHRoot}/{PkgName}" path:

```
    Directory: N:\Tools\7-Zip


Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
da----        15/04/2023     13:27                Lang
-a----        27/12/2021     10:00         112890 7-zip.chm
-a----        26/12/2021     14:00          93696 7-zip.dll
-a----        26/12/2021     14:00          62976 7-zip32.dll
-a----        26/12/2021     14:00        1710080 7z.dll
-a----        26/12/2021     14:00         535040 7z.exe
-a----        26/12/2021     14:00         215040 7z.sfx
-a----        26/12/2021     14:00         193536 7zCon.sfx
-a----        26/12/2021     14:00         945664 7zFM.exe
-a----        15/04/2023     15:31            766 7zFM.ico
-a----        26/12/2021     14:00         667136 7zG.exe
-a----        28/01/2018     09:00            366 descript.ion
-a----        27/12/2021     08:52          54604 History.txt
-a----        17/01/2021     15:12           3990 License.txt
-a----        26/12/2021     13:54           1702 readme.txt
-a----        10/01/2023     13:02           2153 test.exe.lnk
-a----        26/12/2021     14:00          14848 Uninstall.exe
```



#### Step 2: Run Install

You'll be allowed to select the list of packages to sync periodically. (ie select which yaml files to auto-apply)

At the next step, confirm your `{LSHRoot}` path.

This is the path where you will keep all your portable apps.

Note: The `LightSync.ps1` script can be located at a different location.

```
.\LightSync.ps1 -Install

DEBUG: [ LightSync.ps1 ]: Starting LightSync
  [x] 7-zip.yaml
  [x] ChatGPT.yaml
  [x] ConEmuPortable.yaml
  [x] EarTrumpet.yaml
  [x] FileZillaPortable.yaml
  [x] FoxitReaderPortable.yaml
  [x] FSViewer.yaml
  [x] GitBashPortable.yaml
  [x] GoogleChromePortable.yaml
  [x] KeePass.yaml
  [x] LibreOfficePortable-7.5.2.yaml
  [x] LogExpert.yaml
  [x] LogitechOptions.yaml
  [x] MyTools.yaml
  [x] Notepad++.yaml
  [x] PomoDoneApp.yaml
  [x] PuttyPortable.yaml
  [x] PWGen.yaml
  [x] Python.yaml
  [x] TelegramDesktopPortable.yaml
  [x] TotalCmd.yaml
  [x] TreeSize.yaml
  [x] VLC.yaml
  [x] VS Code.yaml
  [x] Winamp.yaml
> [ ] WindowsDecrapify.yaml
  [x] WindowsTerminal.yaml


Packages     : {7-zip.yaml, ChatGPT.yaml, ConEmuPortable.yaml, EarTrumpet.yaml...}
PSPath       : Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER\SOFTWARE\LightSync
PSParentPath : Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER\SOFTWARE
PSChildName  : LightSync
PSDrive      : HKCU
PSProvider   : Microsoft.PowerShell.Core\Registry

Select LightSync drive and path (current: N:\Tools):
DEBUG: Adding N:\Tools\_PACKAGES to User PATH
DEBUG: >> [ Add-UserPaths ]: Paths `N:\Tools\_PACKAGES` already present, no changes needed.

Actions            : {MSFT_TaskExecAction}
Author             :
Date               :
Description        : Light User Profile Syncing Project for user Lev
Documentation      :
Principal          : MSFT_TaskPrincipal2
SecurityDescriptor :
Settings           : MSFT_TaskSettings3
Source             :
State              : Ready
TaskName           : LightSync.sh - Lev
TaskPath           : \
Triggers           : {MSFT_TaskDailyTrigger}
URI                : \LightSync.sh - Lev
Version            :
PSComputerName     :

Actions            : {MSFT_TaskExecAction}
Author             :
Date               :
Description        : Light User Profile Syncing Project for user Lev
Documentation      :
Principal          : MSFT_TaskPrincipal2
SecurityDescriptor :
Settings           : MSFT_TaskSettings3
Source             :
State              : Ready
TaskName           : LightSync.sh - Lev
TaskPath           : \
Triggers           : {MSFT_TaskDailyTrigger}
URI                : \LightSync.sh - Lev
Version            :
PSComputerName     :

```

#### Step 3: Perform a Manual Sync (Optional)

An ad-hoc sync of a package file can also be performed.

In this mode, a scheduled task will not be installed.

```
.\LightSync.ps1 -PackageFile .\packages\7-zip.yaml
```

All package files can be synced as well:

```
./LightSync.ps1
```


### Recommended use with Dropbox

I'm using the following process to sync my portable apps and configs across multiple machines using Dropbox.

#### Step 1: Install Dropbox

Just a standard Dropbox install, it can be to any location.

#### Step 2: Create a substed drive

It is a good idea to abstract out the Dropbox sync path, because this often changes between machines.

Subst is a built-in Windows tool that can do this.

eg:
```
subst N: "C:\Users\Lev\Dropbox\"
```
You can put this script in your `shell:startup` folder.

One caveat is that any elevated process will not have access to a substed path by default, unless you also re-run the subst command as admin.


#### Step 3: Install any portable apps

Extract your portable apps under the virtual `N:\Tools` path.

The folder will get synced by Dropbox.

#### Step 4: Clone the 'LightSync' and 'useful' repos

Clone the two repos into the same parent.

It's best to put these on the `N:` drive as well, such as the yaml files will get synced automatically.

```
mkdir n:\src
cd n:\src

git clone https://github.com/levid0s/useful.git
git clone https://github.com/levid0s/LightSync.ps1.git
```

### Step 5: Install LightSync as a scheduled task

```
LightSync.ps1 -Install
```

