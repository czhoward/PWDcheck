# PWDcheck

Script to identify weak passwords in use from an AD dump.

This was originally (and still is) a quickly knocked together solution to running automated checks against AD accounts to identify and force people to change weak passwords.  It's all pretty simple, so you might just want to use it as a guide to stepping through the process manually to get an idea of how many people are using too simplistic passwords. I recommend checking the [NIST](https://www.nist.gov/) guidelines for latest best practices in password management.

At the end of this script all accounts that were listed with simple passwords have the password age reset to 0 forcing a password change at next login. You can quite easily add a `blat` here that emails the user with an explanation of good password guidelines.

This runs on a Windows server with a copy of the AD database dumped out using the `ntdsutil` tool.  It then uses a variety of open source or free (blat) to use tools to check for low hanging fruit.

Note: this was written over 5 years ago, probably a little more and no doubt things have moved on, I recommend checking out [DSInternals](https://www.dsinternals.com/en/) the creator of the `ntdsaudit` tool, but this may still be useful if your infrastructure hasn't moved on yet ;-)

This is provided as is, I no longer have access to an AD environment to test or rework this solution, but I'm pretty certain it could be re-written in powershell now removing some of the tooling dependencies and improving the overall quality of the code.
