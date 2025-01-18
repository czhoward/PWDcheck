rem @echo off 
setlocal enabledelayedexpansion

REM Takes an AD Dump file, runs NTDS audit to extract password hashes, 
REM cracks them with John the Ripper and then forces users with weak passwords to change them at next logon
REM this uses the Jumbo version of John the Ripper and the ntdsaudit tool from the DSInternals project
REM it also uses the AdFind tool from Joeware.net and Blat for email notifications as well as a windows compatible cut command
REM it is designed to be run on a Windows Server 2012 R2 system with the Active Directory dump files copied to the local system
REM but should also work on Windows 2016 and 2019
REM It is  designed to be run as a scheduled task with the account running the task having the necessary permissions to reset user passwords and force change at next logon

REM Generate the AD dump files on an AD server ntdsutil.exe 'ac i ntds' 'ifm' 'create full c:\PWDcheck' q q

REM BLAT can be found at https://www.blat.net/
REM JOHN can be found at https://github.com/openwall/john
REM NTDSAudit can be found at https://github.com/dionach/NtdsAudit
REM AdFind can be found at https://www.joeware.net/freetools/tools/adfind/index.htm
REM A windows compatible cut command can be found at https://github.com/gnuwin32/GnuWin

REM email settings configure these to your environment
set server=-server SMTPServer
set eMailTo=ADMINs@EMAIL.ADDRESS
set eMailFrom=DoNotRespond@EMAIL.ADDRESS

REM location of files - configure these to your environment
set base=c:\PWDcheck
set conf=%BASE%\conf
set scratch=%BASE%\ADdump
set tools=%BASE%\apps
set jtr=%TOOLS%\jumbo\run
set output=%BASE%\AD-output
rem set wordlist=%JTR%\PwnedPasswordTop100k.txt
set wordlist=%JTR%\PasswordTop100k.txt
rem set wordlist=%JTR%\wordlist.txt

IF NOT EXIST %OUTPUT% mkdir %OUTPUT%

REM get day of week 
for /f "tokens=*" %%d in ('wmic path win32_localtime get dayofweek ^| findstr "[0-9]"') do set "Day=%%d"
REM strip trailling spaces
set Day=%Day:~0,1%
REM and figure out yesterday (not strictly necessary if not giving people notice!)
set /a Yesterday=%Day%-1
IF "%Day%"=="1" (SET Yesterday=5)

set log=%BASE%\%DAY%.log
echo Starting Process > %LOG%

REM Check AD dump files are from today
forfiles /P %SCRATCH% /D +0 /S 
IF NOT errorlevel 0 goto skip

REM Check if the previous day's output file exists before exporting details
IF EXIST %OUTPUT%\%Yesterday%.std.txt (
    echo Export details of users who were identified on last run - start >> %LOG%
    powershell.exe -nologo -noprofile -noninteractive -command "Get-Content %OUTPUT%\%Yesterday%.std.txt | Get-ADUser -Properties PasswordExpired,PasswordLastSet | Export-CSV %OUTPUT%\%Yesterday%.std.review.csv"
    echo Export details of users who were identified on last run - complete >> %LOG%
) ELSE (
    echo Previous day's output file not found, skipping export step >> %LOG%
)

REM dump passwords and accounts out of AD dump.  
REM Note if ntdsaudit crashes complaining of corrupt secondary index it is probably because you are running on a system different to the OS the dump was taken on
echo NTDS dump process - start >> %LOG%
%TOOLS%\ntdsaudit "%SCRATCH%\Active Directory\ntds.dit" -s "%SCRATCH%\registry\SYSTEM" -p %OUTPUT%\%Day%.pwdump.txt 
echo NTDS dump process - complete >> %LOG%

REM crack AD
echo Crack process - start >> %LOG%
%JTR%\john.exe -format=NT --wordlist=%WORDLIST% %OUTPUT%\%Day%.pwdump.txt --rules:simple
move %JTR%\john.pot %OUTPUT%\%Day%.pot
echo Crack process - complete >> %LOG%

REM get list of cracked passwords
echo Manipulate data process - start >> %LOG%
type %OUTPUT%\%Day%.pot | %TOOLS%\cut -f3 -d$  | %TOOLS%\cut -f1 -d: > %OUTPUT%\%Day%.hash.txt

REM get user with cracked passwords accounts
findstr /I /G:%OUTPUT%\%Day%.hash.txt %OUTPUT%\%Day%.pwdump.txt | %TOOLS%\cut -f1 -d: | %TOOLS%\cut -f2 -d\  > %OUTPUT%\%Day%.users.txt

REM generate list of disabled AND expired accounts to use as exclusion filter
set disabled=%OUTPUT%\%Day%.disabled.txt
%TOOLS%\AdFind -default -bit -f userAccountControl:AND:=2 sAMAccountName | findstr /I samaccountname | %TOOLS%\cut -d" " -f2 > %DISABLED%
%TOOLS%\AdFind -default -sc users_accexpired sAMAccountName | findstr /I samaccountname | %TOOLS%\cut -d" " -f2 >> %DISABLED%

REM break down list into standard accounts, in this organisation defined as four characters followed by four numbers eg AAAA9999
REM You will need to change this depending on your account naming convention
findstr /b "[a-zA-Z][a-zA-Z][a-zA-Z][a-zA-Z][0-9][0-9][0-9][0-9]\>" %OUTPUT%\%Day%.users.txt | findstr /i /v /g:%DISABLED% > %OUTPUT%\%Day%.std.txt
findstr /b /v "[a-zA-Z][a-zA-Z][a-zA-Z][a-zA-Z][0-9][0-9][0-9][0-9]\>" %OUTPUT%\%Day%.users.txt | findstr /i /v /g:%DISABLED% | findstr /v /g:%CONF%\non-standard.exclude > %OUTPUT%\%Day%.nonstd.txt
echo Manipulate data process - complete >> %LOG%

REM Send non standard users list to IT
set subj=-s "List of Non-Standard User Accounts with Weak Passwords"
set attach=-attach %OUTPUT%\%Day%.nonstd.txt
%TOOLS%\blat.exe %CONF%\nonstd.email -to %eMailTo% -f %eMailFrom% %subj% %server% %attach%

REM Set those accounts that have weak passwords to change password 
REM note this server's account has been delegated "reset user passwords and force change at next logon" to the Accounts OU
echo Force failed accounts to change password at next logon - start >> %LOG%
for /f %%a in (%OUTPUT%\%Day%.std.txt) do (
	cscript -nologo %BASE%\ExpirePWD.vbs %%a
)
echo Force failed accounts to change password at next logon - complete >> %LOG%

REM delete AD files
rd /s/q "%SCRATCH%\Active Directory"
rd /s/q "%SCRATCH%\registry"

exit /b

:skip
set subj=-s "Issue with password check script - AD copy out of date"
%TOOLS%\blat.exe %CONF%\error.email -to %eMailTo% -f %eMailFrom% %subj% %server%
