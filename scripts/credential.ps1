<#
.SYNOPSIS
  Store / retrieve / delete a SQL Server password in Windows Credential Manager (generic
  credential, user-scoped, DPAPI-encrypted at rest). No third-party modules.

.DESCRIPTION
  Bridges Credential Manager to sqlcmd, which has no native "read from Credential Manager"
  auth mode. The audit skill calls `get` inside the same shell as sqlcmd to populate the
  SQLCMDPASSWORD environment variable, then clears it — the secret never touches the command
  line or the transcript.

  Target naming scheme: "sql-audit:<server>:<user>".

.PARAMETER Action  store | get | delete | list
.PARAMETER Server  SQL Server address (part of the target key)
.PARAMETER User    SQL login (stored as the credential UserName; part of the target key)
.PARAMETER Target  Override the full target name (optional)

.EXAMPLE
  # one-time, run it yourself so the password is never seen by the agent:
  ! powershell -File scripts/credential.ps1 store -Server db.example.com -User auditor
.EXAMPLE
  # what the skill runs internally (password -> env var -> sqlcmd -> cleared):
  $env:SQLCMDPASSWORD = & scripts/credential.ps1 get -Server db.example.com -User auditor
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('store', 'get', 'delete', 'list')]
    [string]$Action,
    [string]$Server,
    [string]$User,
    [string]$Target
)

$ErrorActionPreference = 'Stop'

if (-not ('SqlAudit.CredMan' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace SqlAudit {
    public static class CredMan {
        private const uint GENERIC = 1;
        private const uint PERSIST_LOCAL_MACHINE = 2;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct CREDENTIAL {
            public uint Flags;
            public uint Type;
            public string TargetName;
            public string Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public uint CredentialBlobSize;
            public IntPtr CredentialBlob;
            public uint Persist;
            public uint AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredWriteW(ref CREDENTIAL cred, uint flags);
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredReadW(string target, uint type, uint flags, out IntPtr credPtr);
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredDeleteW(string target, uint type, uint flags);
        [DllImport("advapi32.dll")]
        private static extern void CredFree(IntPtr cred);

        public static void Store(string target, string user, string password) {
            byte[] bytes = System.Text.Encoding.Unicode.GetBytes(password);
            IntPtr blob = Marshal.AllocHGlobal(bytes.Length);
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            try {
                CREDENTIAL c = new CREDENTIAL();
                c.Type = GENERIC;
                c.TargetName = target;
                c.UserName = user;
                c.CredentialBlob = blob;
                c.CredentialBlobSize = (uint)bytes.Length;
                c.Persist = PERSIST_LOCAL_MACHINE;
                if (!CredWriteW(ref c, 0))
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            } finally {
                Marshal.FreeHGlobal(blob);
            }
        }

        public static string Get(string target) {
            IntPtr ptr;
            if (!CredReadW(target, GENERIC, 0, out ptr))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            try {
                CREDENTIAL c = (CREDENTIAL)Marshal.PtrToStructure(ptr, typeof(CREDENTIAL));
                if (c.CredentialBlobSize == 0) return "";
                byte[] bytes = new byte[c.CredentialBlobSize];
                Marshal.Copy(c.CredentialBlob, bytes, 0, (int)c.CredentialBlobSize);
                return System.Text.Encoding.Unicode.GetString(bytes);
            } finally {
                CredFree(ptr);
            }
        }

        public static void Delete(string target) {
            if (!CredDeleteW(target, GENERIC, 0))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
    }
}
'@
}

function Resolve-Target {
    if ($Target) { return $Target }
    if (-not $Server -or -not $User) {
        throw "Provide -Server and -User (or -Target). Target scheme: sql-audit:<server>:<user>"
    }
    return "sql-audit:${Server}:${User}"
}

switch ($Action) {
    'store' {
        $t = Resolve-Target
        $sec = Read-Host "SQL password for $t" -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try {
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            [SqlAudit.CredMan]::Store($t, $User, $plain)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            $plain = $null
        }
        Write-Host "Stored credential '$t' in Windows Credential Manager."
    }
    'get' {
        # Prints ONLY the password to stdout for the caller to capture into SQLCMDPASSWORD.
        [SqlAudit.CredMan]::Get((Resolve-Target))
    }
    'delete' {
        $t = Resolve-Target
        [SqlAudit.CredMan]::Delete($t)
        Write-Host "Deleted credential '$t'."
    }
    'list' {
        # cmdkey lists target names only — it never reveals stored passwords.
        (cmdkey /list) | Select-String -Pattern 'sql-audit:' | ForEach-Object { $_.Line.Trim() }
    }
}
