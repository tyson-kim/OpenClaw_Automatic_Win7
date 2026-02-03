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

' 1. FORCE IGNORE SSL ERRORS (The fix for "Certificate authority is invalid")
' 13056 = 0x3300 = Ignore Unknown CA + Ignore Invalid Date + Ignore Invalid CN + Ignore Invalid Policy
 On Error Resume Next
http.Option(4) = 13056
If Err.Number <> 0 Then
    WScript.Echo "Warning: Could not set SSL Ignore flags."
    Err.Clear
End If
On Error GoTo 0

' 2. Attempt TLS 1.2 (2048) / TLS 1.1 (512) / TLS 1.0 (128)
' If 2048 fails, we hope the SystemDefaultTlsVersions registry key kicks in.
On Error Resume Next
http.Option(9) = 2048 ' Try TLS 1.2
If Err.Number <> 0 Then
   ' If specific TLS 1.2 setting fails, we just proceed.
   ' The Registry fix (enable_tls12.bat) should handle the protocol negotiation.
   Err.Clear
End If
On Error GoTo 0

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
    WScript.Echo "Error: Server returned status " & http.Status
    WScript.Quit 1
End If
