Option Explicit

Function usage()

	Wscript.Echo("Usage:install.vbs /prefix:InstallDirectory /port:ListenPort /pkgurl:PACKAGE_URL /downloaduser:Download_User /downloadpwd:Download_Password /serveraddr:REGISTER_URL /tenant:Tenant")
	Wscript.Echo("")
	Wscript.Echo("/prefix: Directory to install, default:/opt/tagent")
	Wscript.Echo("/listenaddr: Agent listen addr, default:0.0.0.0")
	Wscript.Echo("/port: Agent listen port, default:3939")
	Wscript.Echo("/pkgurl: Agent install package download url, support http|https|ftp")
	Wscript.Echo("/downloaduser: Access download url username, default:none")
	Wscript.Echo("/downloadpwd: Access download url password, defualt:none")
	Wscript.Echo("/serveraddr: Agent register call back http base url")
	Wscript.Echo("/tenant: System tenant")
	Wscript.Echo("")
	Wscript.Echo("Example:install.vbs /port:3939 /pkgurl:""http://abc.com/service/tagent.tar"" /serveraddr:""http://192.168.0.88:8080/autoexecrunner/public/api/rest/tagent/register?tenant=develop"" /tenant:test")
	WScript.Quit(1)
End Function

Function DownloadPkg(pkgUrl, userName, password, savePath, tempPath)
	Wscript.Echo("INFO:download package from " & pkgUrl)
	
	If InStr(1, pkgUrl, "ftp://") = 1 Then
		Dim hostStart, hostEnd, fileStart, ftpHost, remoteDir, remoteFile
		hostStart = 7
		hostEnd = InStr(7, pkgUrl, "/")
		fileStart = InStrRev(pkgUrl, "/") + 1
		ftpHost = Mid(pkgUrl, 7, hostEnd-hostStart)
		remoteDir = Mid(pkgUrl, hostEnd+1, fileStart-hostEnd-1)
		remoteFile = Mid(pkgUrl, fileStart)
		savePath = tempPath & "\" & remoteFile

		Dim objOutStream, objFSO, objShell
		Set objFSO = CreateObject("Scripting.FileSystemObject")
		Set objOutStream = objFSO.OpenTextFile(tempPath & "\session.txt", 2, True)
		With objOutStream
			.WriteLine userName   ' USERNAME
			.WriteLine password     ' Password
			.WriteLine "binary"
			.WriteLine "lcd """ & tempPath & """" ' FOLDER I'm changing into
			.WriteLine "get """ & remoteFile & """ tagent.zip" ' Get all files with today's date in it
			.WriteLine "quit"
			.Close
		End With
		Set objOutStream = Nothing

		Set objShell = CreateObject("WScript.Shell")
		objShell.Run "%comspec% /c FTP -n -i -s:""" & tempPath & "\session.txt""" & " " & """ftpHost""", 0, True
		objFSO.DeleteFile tempPath & "\session.txt", True
		Set objFSO = Nothing
		Set objShell = Nothing
	Else
		Dim xHttp
		Set xHttp = CreateObject("Msxml2.XMLHTTP")
		If IsNull(userName) Or IsEmpty(userName) Then
			xHttp.Open "GET", pkgUrl, 0
		Else
			xHttp.Open "GET", pkgUrl, 0, userName, password
		End If

		'xHttp.setTimeouts 5000, 5000, 10000, 10000   'ms - resolve, connect, send, receive'
		xHttp.setRequestHeader "Authorization", "Basic MY_AUTH_STRING"
		xHttp.Send

		Dim aGet
		Set aGet = CreateObject("ADODB.Stream")
		aGet.Mode = 3
		aGet.Type = 1
		aGet.Open() 
		aGet.Write(xHttp.responseBody)
		aGet.SaveToFile savePath, 2
		Set xHttp = Nothing
	End If
End Function

Dim colArgs
Set colArgs = WScript.Arguments.Named

Dim installPath
installPath = "c:\tagent"
If colArgs.Exists("prefix") Then
	installPath = colArgs.Item("prefix")
End If

Dim listenAddr
listenAddr = "0.0.0.0"
If colArgs.Exists("listenaddr") Then
	listenAddr = colArgs.Item("listenaddr")
End If

Dim port
port = "3939"
If colArgs.Exists("port") Then
	port = colArgs.Item("port")
End If

Dim pkgUrl
If colArgs.Exists("pkgurl") Then
	pkgUrl = colArgs.Item("pkgurl")
End If

Dim userName
If colArgs.Exists("downloaduser") Then
	userName = colArgs.Item("downloaduser")
End If

Dim password
If colArgs.Exists("downloadpwd") Then
	password = colArgs.Item("downloadpwd")
End If

Dim srvAddr
If colArgs.Exists("serveraddr") Then
	srvAddr = colArgs.Item("serveraddr")
End If

Dim tenant
If colArgs.Exists("tenant") Then
	tenant = colArgs.Item("tenant")
End If

IF IsNull(pkgUrl) Or IsEmpty(pkgUrl) Then
	Wscript.Echo("ERROR: option /pkgurl not provided.")
	usage()
End If

Dim wshShell
Set wshShell = WScript.CreateObject("WScript.Shell")
Dim tempPath
tempPath = wshShell.ExpandEnvironmentStrings("%TEMP%")

Dim savePath
savePath = tempPath & "\tagent.zip"

DownloadPkg pkgUrl, userName, password, savePath, tempPath

Wscript.Echo("INFO: Extract package")
Dim fso
Set fso = CreateObject("Scripting.FileSystemObject")
If NOT fso.FolderExists(installPath) Then
	fso.CreateFolder(installPath)
End If

Dim objShell, filesInZip
Set objShell = CreateObject("Shell.Application")
Set filesInZip=objShell.NameSpace(savePath).items
objShell.NameSpace(installPath).CopyHere(filesInZip)
Set fso = Nothing
Set objShell = Nothing

wshShell.CurrentDirectory = installPath

Dim errCode
errCode = wshShell.Run("service-install.bat " & srvAddr & " " & tenant & " " & listenAddr & " " & port, ,True)
Set wshShell = Nothing

If errCode <> 0 Then
	Wscript.Echo("ERROR: Install failed.")
	WScript.Quit(1)
Else
	 Wscript.Echo("INFO: Install success.")
End If
