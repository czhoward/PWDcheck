Option Explicit

' Takes a username, gets the DN and then sets that account password last set date to 0
' causing the user to have to change their password at next login

Const ADS_SCOPE_SUBTREE = 2
Const AD_PROVIDER = "Active Directory Provider"
Const PAGE_SIZE = 1000

Dim strUser, strUserDN, objUser

strUser = Wscript.Arguments(0)

Function distinguish(strObject, strType)
    Dim objRootDSE, strDNSDomain, objConnection, objCommand, objRecordSet

    Select Case LCase(strType)
        Case "computer"
            strObject = strObject & "$"
        Case "user", "group"
            ' Good
        Case Else
            Wscript.Echo "There is an error in the script"
            Exit Function
    End Select

    ' Determine DNS domain name (this could be hard coded).
    Set objRootDSE = GetObject("LDAP://RootDSE")
    strDNSDomain = objRootDSE.Get("defaultNamingContext")

    Set objConnection = CreateObject("ADODB.Connection")
    Set objCommand = CreateObject("ADODB.Command")
    objConnection.Provider = "ADsDSOObject"
    objConnection.Open AD_PROVIDER

    Set objCommand.ActiveConnection = objConnection
    objCommand.CommandText = _
        "Select distinguishedname, Name, Location from 'LDAP://" & strDNSDomain & _
        "' Where objectClass='" & strType & "' and samaccountname='" & strObject & "'"
    objCommand.Properties("Page Size") = PAGE_SIZE
    objCommand.Properties("Searchscope") = ADS_SCOPE_SUBTREE

    On Error Resume Next
    Set objRecordSet = objCommand.Execute
    objRecordSet.MoveFirst 
     
    Do Until objRecordSet.EOF 
       distinguish = objRecordSet.Fields("distinguishedname") 
       objRecordSet.MoveNext 
    Loop 

    objRecordSet.Close
    objConnection.Close
End Function

' Get the fully qualified DN for the account
strUserDN = distinguish(strUser, "user")

If strUserDN <> "" Then
    ' Point to the AD object
    Set objUser = GetObject ("LDAP://" + strUserDN)
    ' Set the password last set to 0 (this sets password to have last been set in 1601!  -1 would be today, these are the only two options that can be configured)
    objUser.Put "pwdLastSet", CLng(0)
    ' Save the change
    objUser.SetInfo
Else
    Wscript.Echo "User not found"
End If
