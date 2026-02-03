Option Explicit

If WScript.Arguments.Count < 2 Then
    WScript.Echo "Usage: download.vbs <URL> <Destination>"
    WScript.Quit 1
End If

Dim url, dest, http, stream, fso

url = WScript.Arguments(0)
dest = WScript.Arguments(1)

Set http = CreateObject("WinHttp.WinHttpRequest.5.1")
http.Open "GET", url, False

' Attempt to enable TLS 1.2 (0x00000800 = 2048)
' This mimics the effect of modernizing the SecureProtocols registry key
' but does it at the application level for this request.
On Error Resume Next
http.Option(9) = 2048
If Err.Number <> 0 Then
    WScript.Echo "Warning: Could not set TLS 1.2 option. Detailed error: " & Err.Description
    Err.Clear
End If
On Error GoTo 0

' Send request
WScript.Echo "Downloading: " & url
http.Send

If http.Status = 200 Then
    Set stream = CreateObject("ADODB.Stream")
    stream.Open
    stream.Type = 1 ' Binary
    stream.Write http.ResponseBody
    stream.Position = 0
    
    Set fso = CreateObject("Scripting.FileSystemObject")
    If fso.FileExists(dest) Then fso.DeleteFile dest
    
    stream.SaveToFile dest, 2
    stream.Close
    WScript.Echo "Success: File saved to " & dest
    WScript.Quit 0
Else
    WScript.Echo "Error: CreateObject failed or Server returned status " & http.Status
    WScript.Quit 1
End If
