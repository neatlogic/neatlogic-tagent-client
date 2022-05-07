Set pkgUrl = ""
Set args = WScript.Arguments
If args.Count = 1 Then
	pkgUrl = WScript.Arguments(0)
Else
	Wscript.Echo("Usage: install.vbs <pkgUrl>")
	WScript.Quit(1)
End If

Set wshShell = CreateObject("WScript.Shell")
Set savePath wshShell.ExpandEnvironmentStrings("%TEMP%\tagent.zip")

Wscript.Echo("INFO:download package from " & pkgUrl)
Set Post = CreateObject("Msxml2.XMLHTTP")
Set Shell = CreateObject("Wscript.Shell")
Post.Open("GET", pkgUrl, 0)
Post.Send()
Set aGet = CreateObject("ADODB.Stream")
aGet.Mode = 3
aGet.Type = 1
aGet.Open() 
aGet.Write(Post.responseBody)
aGet.SaveToFile(savePath, 2)

Wscript.Echo("INFO:extract package");
Set installPath="C:\tagent\"
Set fso = CreateObject("Scripting.FileSystemObject")
If NOT fso.FolderExists(installPath) Then
	fso.CreateFolder(installPath)
End If

set objShell = CreateObject("Shell.Application")
set filesInZip=objShell.NameSpace(savePath).items
objShell.NameSpace(installPath).CopyHere(filesInZip)
Set fso = Nothing
Set objShell = Nothing

wshShell.CurrentDirectory = installPath
Set exitCode = wshShell.Run("winservice-install.bat");
If exitCode != 0 Then
	Wscript.Echo("ERROR:install failed.")
	WScript.Quit(1);
End If
