#encoding: UTF-8
require 'puppet/provider'
require 'puppet/util/windows'

class SecurityPolicy
    attr_reader :wmic_cmd
    EVENT_TYPES = ["Success,Failure", "Success", "Failure", "No Auditing", 0, 1, 2, 3]

    def initialize
    end

    def user_to_sid(value)
        sid = Puppet::Util::Windows::SID.name_to_sid(value)
        unless sid.nil?
            '*' + sid
        else
            value
        end
    end

    # convert the sid to a user
    def sid_to_user(value)
        value = value.gsub(/(^\*)/ , '')
        user = Puppet::Util::Windows::SID.sid_to_name(value)
        unless user.nil?
           user
        else
           value
        end
    end

    def convert_privilege_right(ensure_value, policy_value)
        # we need to convert users to sids first
        if ensure_value.to_s == 'absent'
            pv = ''
        else
            sids = Array.new
            policy_value.split(",").sort.each do |suser|
                suser.strip!
                sids << user_to_sid(suser)
            end
            pv = sids.sort.join(",")
        end
    end

    # converts the policy value inside the policy hash to conform to the secedit standards
    def convert_policy_hash(policy_hash)
        case policy_hash[:policy_type]
            when 'Privilege Rights'
                value = convert_privilege_right(policy_hash[:ensure], policy_hash[:policy_value])
            when 'Event Audit'
                value = event_to_audit_id(policy_hash[:policy_value])
            when 'Registry Values'
                value = SecurityPolicy.convert_registry_value(policy_hash[:name], policy_hash[:policy_value])
            else
                value = policy_hash[:policy_value]
        end
        policy_hash[:policy_value] = value
        policy_hash
    end

    # Converts a event number to a word
    def self.event_audit_mapper(policy_value)
        case policy_value.to_s
            when 3
                return "Success,Failure"
            when 2
                return "Failure"
            when 1
                return "Success"
            else
                return "No auditing"
        end
    end

    # Converts a event number to a word
    def self.event_to_audit_id(event_audit_name)
        case event_audit_name
            when "Success,Failure"
                return 3
            when "Failure"
                return 2
            when "Success"
                return 1
            when 'No auditing'
                return 0
            else
                return event_audit_name
        end
    end

    # returns the key and hash value given the policy name
    def self.find_mapping_from_policy_name(name)
        key, value = lsp_mapping.find do |key,hash|
            hash[:name] == name
        end
        unless key && value
            raise KeyError, "#{name} is not a valid policy"
        end
        return key, value
    end

    # returns the key and hash value given the policy desc
    def self.find_mapping_from_policy_desc(desc)
        name = desc.downcase
        value = nil
        key, value = lsp_mapping.find do |key, hash|
            key.downcase == name
        end
        unless value
            raise KeyError, "#{desc} is not a valid policy"
        end
        return value
    end

    def self.valid_lsp?(name)
        lsp_mapping.keys.include?(name)
    end

    def self.convert_registry_value(name, value)
        value = value.to_s
        return value if value.split(',').count > 1
        policy_hash = find_mapping_from_policy_desc(name)
        "#{policy_hash[:reg_type]},#{value}"
    end

    # converts the policy value to machine values
    def self.convert_policy_value(policy_hash, value)
        sp = SecurityPolicy.new
        # I would rather not have to look this info up, but the type code will not always have this info handy
        # without knowing the policy type we can't figure out what to convert
        policy_type = find_mapping_from_policy_desc(policy_hash[:name])[:policy_type]
        case policy_type.to_s
            when 'Privilege Rights'
                sp.convert_privilege_right(policy_hash[:ensure], value)
            when 'Event Audit'
                event_to_audit_id(value)
            when 'Registry Values'
                # convert the value to a datatype/value
                convert_registry_value(policy_hash[:name], value)
            else
                value
        end
    end

    def self.lsp_mapping
        @lsp_mapping ||= {
            # Password policy Mappings
            'Enforce password history' => {
                :name => 'PasswordHistorySize',
                :policy_type => 'System Access',
            },
            'Maximum password age' => {
                :name => 'MaximumPasswordAge',
                :policy_type => 'System Access',
            },
            'Minimum password age' => {
                :name => 'MinimumPasswordAge',
                :policy_type => 'System Access',
            },
            'Minimum password length' => {
                :name => 'MinimumPasswordLength',
                :policy_type => 'System Access',
            },
            'Password must meet complexity requirements' => {
                :name => 'PasswordComplexity',
                :policy_type => 'System Access',
            },
            'Store passwords using reversible encryption' => {
                :name => 'ClearTextPassword',
                :policy_type => 'System Access',
            },
            'Account lockout threshold' => {
                :name => 'LockoutBadCount',
                :policy_type => 'System Access',
            },
            'Account lockout duration' => {
                :name => 'LockoutDuration',
                :policy_type => 'System Access',
            },
            'Reset account lockout counter after' => {
                :name => 'ResetLockoutCount',
                :policy_type => 'System Access',
            },
            'Accounts: Rename administrator account' => {
                :name => 'NewAdministratorName',
                :policy_type => 'System Access',
                :data_type => :quoted_string
            },
            'Accounts: Rename guest account' => {
                :name => 'NewGuestName',
                :policy_type => 'System Access',
                :data_type => :quoted_string
            },
            'Accounts: Require Login to Change Password' => {
                :name => 'RequireLogonToChangePassword',
                :policy_type => 'System Access'
            },
            'ForceLogoffWhenHourExpire' => {
                :name => 'ForceLogoffWhenHourExpire',
                :policy_type => 'System Access'
            },
            'LSAAnonymousNameLookup' => {
                :name => 'LSAAnonymousNameLookup',
                :policy_type => 'System Access'
            },
            'EnableAdminAccount' => {
                :name => 'EnableAdminAccount',
                :policy_type => 'System Access'
            },
            "EnableGuestAccount"=>{
                :name=>"EnableGuestAccount",
                :policy_type=>"System Access"
            },
            # Audit Policy Mappings
            "AuditProcessTracking" => {
                :name => "AuditProcessTracking",
                :policy_type => "Event Audit"
            },
            'Audit account logon events' => {
                :name => 'AuditAccountLogon',
                :policy_type => 'Event Audit',
            },
            'Audit account management' => {
                :name => 'AuditAccountManage',
                :policy_type => 'Event Audit',
            },
            'Audit directory service access' => {
                :name => 'AuditDSAccess',
                :policy_type => 'Event Audit',
            },
            'Audit logon events' => {
                :name => 'AuditLogonEvents',
                :policy_type => 'Event Audit',
            },
            'Audit object access' => {
                :name => 'AuditObjectAccess',
                :policy_type => 'Event Audit',
            },
            'Audit policy change' => {
                :name => 'AuditPolicyChange',
                :policy_type => 'Event Audit',
            },
            'Audit privilege use' => {
                :name => 'AuditPrivilegeUse',
                :policy_type => 'Event Audit',
            },
            'Audit process tracking' => {
                :name => 'AuditProcessTraking',
                :policy_type => 'Event Audit',
            },
            'Audit system events' => {
                :name => 'AuditSystemEvents',
                :policy_type => 'Event Audit',
            },
            'Audit: Force audit policy subcategory settings (Windows Vista or later) to override audit policy category settings' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\SCENoApplyLegacyAuditPolicy',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            #User rights mapping
            'Access Credential Manager as a trusted caller' => {
                :name => 'SeTrustedCredManAccessPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Access this computer from the network' => {
                :name => 'SeNetworkLogonRight',
                :policy_type => 'Privilege Rights',
            },
            'Act as part of the operating system' => {
                :name => 'SeTcbPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Add workstations to domain' => {
                :name => 'SeMachineAccountPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Adjust memory quotas for a process' => {
                :name => 'SeIncreaseQuotaPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Allow log on locally' => {
                :name => 'SeInteractiveLogonRight',
                :policy_type => 'Privilege Rights',
            },
            'Allow log on through Remote Desktop Services' => {
                :name => 'SeRemoteInteractiveLogonRight',
                :policy_type => 'Privilege Rights',
            },
            'Back up files and directories' => {
                :name => 'SeBackupPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Bypass traverse checking' => {
                :name => 'SeChangeNotifyPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Change the system time' => {
                :name => 'SeSystemtimePrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Change the time zone' => {
                :name => 'SeTimeZonePrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Create a pagefile' => {
                :name => 'SeCreatePagefilePrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Create a token object' => {
                :name => 'SeCreateTokenPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Create global objects' => {
                :name => 'SeCreateGlobalPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Create permanent shared objects' => {
                :name => 'SeCreatePermanentPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Create symbolic links' => {
                :name => 'SeCreateSymbolicLinkPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Debug programs' => {
                :name => 'SeDebugPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Deny access to this computer from the network' => {
                :name => 'SeDenyNetworkLogonRight',
                :policy_type => 'Privilege Rights',
            },
            'Deny log on as a batch job' => {
                :name => 'SeDenyBatchLogonRight',
                :policy_type => 'Privilege Rights',
            },
            'Deny log on as a service' => {
                :name => 'SeDenyServiceLogonRight',
                :policy_type => 'Privilege Rights',
            },
            'Deny log on locally' => {
                :name => 'SeDenyInteractiveLogonRight',
                :policy_type => 'Privilege Rights',
            },
            'Deny log on through Remote Desktop Services' => {
                :name => 'SeDenyRemoteInteractiveLogonRight',
                :policy_type => 'Privilege Rights',
            },
            'Enable computer and user accounts to be trusted for delegation' => {
                :name => 'SeEnableDelegationPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Force shutdown from a remote system' => {
                :name => 'SeRemoteShutdownPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Generate security audits' => {
                :name => 'SeAuditPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Impersonate a client after authentication' => {
                :name => 'SeImpersonatePrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Increase a process working set' => {
                :name => 'SeIncreaseWorkingSetPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Increase scheduling priority' => {
                :name => 'SeIncreaseBasePriorityPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Load and unload device drivers' => {
                :name => 'SeLoadDriverPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Lock pages in memory' => {
                :name => 'SeLockMemoryPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Log on as a batch job' => {
                :name => 'SeBatchLogonRight',
                :policy_type => 'Privilege Rights',
            },
            'Log on as a service' => {
                :name => 'SeServiceLogonRight',
                :policy_type => 'Privilege Rights',
            },
            'Manage auditing and security log' => {
                :name => 'SeSecurityPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Modify an object label' => {
                :name => 'SeRelabelPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Modify firmware environment values' => {
                :name => 'SeSystemEnvironmentPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Perform volume maintenance tasks' => {
                :name => 'SeManageVolumePrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Profile single process' => {
                :name => 'SeProfileSingleProcessPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Profile system performance' => {
                :name => 'SeSystemProfilePrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Remove computer from docking station' => {
                :name => 'SeUndockPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Replace a process level token' => {
                :name => 'SeAssignPrimaryTokenPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Restore files and directories' => {
                :name => 'SeRestorePrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Shut down the system' => {
                :name => 'SeShutdownPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Synchronize directory service data' => {
                :name => 'SeSyncAgentPrivilege',
                :policy_type => 'Privilege Rights',
            },
            'Take ownership of files or other objects' => {
                :name => 'SeTakeOwnershipPrivilege',
                :policy_type => 'Privilege Rights',
            },
            #Registry Keys
            'Recovery console: Allow automatic administrative logon' => {
                :name => 'MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Setup\RecoveryConsole\SecurityLevel',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Recovery console: Allow floppy copy and access to all drives and all folders' => {
                :name => 'MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Setup\RecoveryConsole\SetCommand',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Interactive logon: Number of previous logons to cache (in case domain controller is not available)' => {
                :name => 'MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\CachedLogonsCount',
                :reg_type => '1',
                :policy_type => 'Registry Values',
            },
            'Interactive logon: Require Domain Controller authentication to unlock workstation' => {
                :name => 'MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\ForceUnlockLogon',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Interactive logon: Prompt user to change password before expiration' => {
                :name => 'MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\PasswordExpiryWarning',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Interactive logon: Smart card removal behavior' => {
                :name => 'MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\ScRemoveOption',
                :reg_type => '1',
                :policy_type => 'Registry Values',
            },
            'User Account Control: Behavior of the elevation prompt for administrators in Admin Approval Mode' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\ConsentPromptBehaviorAdmin',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'User Account Control: Behavior of the elevation prompt for standard users' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\ConsentPromptBehaviorUser',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Interactive logon: Do not require CTRL+ALT+DEL' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\DisableCAD',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Interactive logon: Do not display last user name' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\DontDisplayLastUserName',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Interactive logon: Do not display username at sign-in' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\DontDisplayUserName',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'User Account Control: Detect application installations and prompt for elevation' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\EnableInstallerDetection',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'User Account Control: Run all administrators in Admin Approval Mode' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\EnableLUA',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'User Account Control: Only elevate UIAccess applicaitons that are installed in secure locations' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\EnableSecureUIAPaths',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'User Account Control: Allow UIAccess applications to prompt for elevation without using the secure desktop' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\EnableUIADesktopToggle',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'User Account Control: Virtualize file and registry write failures to per-user locations' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\EnableVirtualization',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'User Account Control: Admin Approval Mode for the built-in Administrator account' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\FilterAdministratorToken',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Interactive logon: Message title for users attempting to log on' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\LegalNoticeCaption',
                :reg_type => '1',
                :policy_type => 'Registry Values',
            },
            'Interactive logon: Message text for users attempting to log on' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\LegalNoticeText',
                :reg_type => '1',
                :policy_type => 'Registry Values',
            },
            'User Account Control: Switch to the secure desktop when prompting for elevation' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\PromptOnSecureDesktop',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Interactive logon: Require smart card' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\ScForceOption',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Shutdown: Allow system to be shut down without having to log on' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\ShutdownWithoutLogon',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'User Account Control: Only elevate executables that are signed and validated' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\ValidateAdminCodeSignatures',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'System settings: Use Certificate Rules on Windows Executables for Software Restriction Policies' => {
                :name => 'MACHINE\Software\Policies\Microsoft\Windows\Safer\CodeIdentifiers\AuthenticodeEnabled',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Audit: Audit the access of global system objects' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\AuditBaseObjects',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Audit: Shut down system immediately if unable to log security audits' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\CrashOnAuditFail',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Network access: Do not allow storage of passwords and credentials for network authentication' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\DisableDomainCreds',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'System cryptography: Use FIPS compliant algorithms for encryption, hashing, and signing' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\FIPSAlgorithmPolicy\Enabled',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'System cryptography: Force strong key protection for user keys stored on the computer' => {
                :name => 'MACHINE\Software\Policies\Microsoft\Cryptography\ForceKeyProtection',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Audit: Audit the use of Backup and Restore privilege' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\FullPrivilegeAuditing',
                :reg_type => '3',
                :policy_type => 'Registry Values',
            },
            'Accounts: Block Microsoft accounts' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\NoConnectedUser',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Accounts: Limit local account use of blank passwords to console logon only' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\LimitBlankPasswordUse',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Network security: Allow Local System to use computer identity for NTLM' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\UseMachineId',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Devices: Restrict CD-ROM access to locally logged-on user only' => {
                :name => 'MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\AllocateCDRoms',
                :reg_type => '1',
                :policy_type => 'Registry Values',
            },
            'Devices: Restrict floppy access to locally logged-on user only' => {
                :name => 'MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\AllocateFloppies',
                :reg_type => '1',
                :policy_type => 'Registry Values',
            },
            'Devices: Allowed to format and eject removable media' => {
                :name => 'MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\AllocateDASD',
                :reg_type => '1',
                :policy_type => 'Registry Values',
            },
            'Devices: Prevent users from installing printer drivers' => {
              :name => 'MACHINE\System\CurrentControlSet\Control\Print\Providers\LanMan Print Services\Servers\AddPrinterDrivers',
              :reg_type => '4',
              :policy_type => 'Registry Values',
            },              
            'Devices: Allow undock without having to log on' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\UndockWithoutLogon',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Domain member: Digitally encrypt or sign secure channel data (always)' => {
                :name => 'MACHINE\System\CurrentControlSet\Services\Netlogon\Parameters\RequireSignOrSeal',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Domain member: Digitally encrypt secure channel data (when possible)' => {
                :name => 'MACHINE\System\CurrentControlSet\Services\Netlogon\Parameters\SealSecureChannel',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Domain member: Digitally sign secure channel data (when possible)' => {
                :name => 'MACHINE\System\CurrentControlSet\Services\Netlogon\Parameters\SignSecureChannel',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Domain member: Disable machine account password changes' => {
                :name => 'MACHINE\System\CurrentControlSet\Services\Netlogon\Parameters\DisablePasswordChange',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Domain member: Maximum machine account password age' => {
                :name => 'MACHINE\System\CurrentControlSet\Services\Netlogon\Parameters\MaximumPasswordAge',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Interactive logon: Display user information when the session is locked' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\DontDisplayLockedUserId',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Interactive logon: Machine inactivity limit' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\InactivityTimeoutSecs',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Interactive logon: Machine account lockout threshold' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\MaxDevicePasswordFailedAttempts',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'ForceGuest' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\ForceGuest',
                :policy_type => "Registry Values",
                :reg_type => "4"
            },
            'Microsoft network client: Digitally sign communications (always)' => {
                :name => 'MACHINE\System\CurrentControlSet\Services\LanmanWorkstation\Parameters\RequireSecuritySignature',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Microsoft network client: Digitally sign communications (if server agrees)' => {
                :name => 'MACHINE\System\CurrentControlSet\Services\LanmanWorkstation\Parameters\EnableSecuritySignature',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Microsoft network client: Send unencrypted password to third-party SMB servers' => {
                :name => 'MACHINE\System\CurrentControlSet\Services\LanmanWorkstation\Parameters\EnablePlainTextPassword',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Microsoft network server: Server SPN target name validation level' => {
                :name => 'MACHINE\System\CurrentControlSet\Services\LanManServer\Parameters\SmbServerNameHardeningLevel',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Microsoft network server: Amount of idle time required before suspending session' => {
                :name => 'MACHINE\System\CurrentControlSet\Services\LanManServer\Parameters\AutoDisconnect',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Microsoft network server: Digitally sign communications (always)' => {
                :name => 'MACHINE\System\CurrentControlSet\Services\LanManServer\Parameters\RequireSecuritySignature',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Microsoft network server: Digitally sign communications (if client agrees)' => {
                :name => 'MACHINE\System\CurrentControlSet\Services\LanManServer\Parameters\EnableSecuritySignature',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Microsoft network server: Disconnect clients when logon hours expire' => {
                :name => 'MACHINE\System\CurrentControlSet\Services\LanManServer\Parameters\EnableForcedLogOff',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Microsoft network server: Attempt S4U2Self to obtain claim information' => {
                :name => 'MACHINE\System\CurrentControlSet\Services\LanManServer\Parameters\EnableS4U2SelfForClaims',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Network access: Named Pipes that can be accessed anonymously' => {
                :name => 'MACHINE\System\CurrentControlSet\Services\LanManServer\Parameters\NullSessionPipes',
                :reg_type => '7',
                :policy_type => 'Registry Values',
            },
            'Network access: Let Everyone permissions apply to anonymous users' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\EveryoneIncludesAnonymous',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Network access: Do not allow anonymous enumeration of SAM accounts and shares' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\RestrictAnonymous',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Network access: Do not allow anonymous enumeration of SAM accounts' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\RestrictAnonymousSAM',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Network access: Remotely accessible registry paths and sub-paths' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\SecurePipeServers\Winreg\AllowedPaths\Machine',
                :reg_type => '7',
                :policy_type => 'Registry Values',
            },
            'Network access: Remotely accessible registry paths' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\SecurePipeServers\Winreg\AllowedExactPaths\Machine',
                :reg_type => '7',
                :policy_type => 'Registry Values',
            },
            'Network Access: Restrict anonymous access to Named Pipes and Shares' => {
                :name => 'MACHINE\System\CurrentControlSet\Services\LanManServer\Parameters\RestrictNullSessAccess',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Network access: Restrict clients allowed to make remote calls to SAM' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\RestrictRemoteSAM',
                :reg_type => '1',
                :policy_type => 'Registry Values',
            },
            'Network Security: Minimum session security for NTLM SSP based (including secure RPC) servers' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\MSV1_0\NTLMMinServerSec',
                :policy_type => 'Registry Values',
                :reg_type => '4'
            },
            'MSS: (SafeDllSearchMode) Enable Safe DLL search mode' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Session Manager\SafeDllSearchMode',
                :policy_type => 'Registry Values',
                :reg_type => '4'
            },
            'System settings: Optional subsystems' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Session Manager\SubSystems\optional',
                :policy_type => 'Registry Values',
                :reg_type => '7'
            },
            'AutoAdminLogon' => {
                :name => 'MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\AutoAdminLogon',
                :policy_type => 'Registry Values',
                :reg_type => '1'
            },
            'AutoShareServer' => {
                :name => 'MACHINE\System\CurrentControlSet\Services\LanmanServer\Parameters\AutoShareServer',
                :policy_type => 'Registry Values',
                :reg_type => '1'
            },
            'Shutdown: Clear virtual memory pagefile' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Session Manager\Memory Management\ClearPageFileAtShutdown',
                :policy_type => 'Registry Values',
                :reg_type => '4'
            },
            'System Object: Require Case Insensitivity for Non-Windows Subsystems' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Session Manager\Kernel\ObCaseInsensitive',
                :policy_type => 'Registry Values',
                :reg_type => '1'
            },
            'Network security: LAN Manager authentication level' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\LmCompatibilityLevel',
                :policy_type => 'Registry Values',
                :reg_type => '4'
            },
            'Network security: Minimum session security for NTLM SSP based (including secure RPC) clients' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\MSV1_0\NTLMMinClientSec',
                :reg_type => '4',
                :policy_type => 'Registry Values',
            },
            'Network security: LDAP client signing requirements' => {
                :name => 'MACHINE\System\CurrentControlSet\Services\LDAP\LDAPClientIntegrity',
                :policy_type => 'Registry Values',
                :reg_type => '4'
            },
            'Network security: Do not store LAN Manager hash value on next password change' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\NoLMHash',
                :policy_type => 'Registry Values',
                :reg_type => '4'
            },
            'Network security: Allow PKU2U authentication requests to this computer to use online identities' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\pku2u\AllowOnlineID',
                :policy_type => 'Registry Values',
                :reg_type => '4'
            },
            'Restrict Access to Base System Objects' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Session Manager\ProtectionMode',
                :policy_type => 'Registry Values',
                :reg_type => '4'
            },
            'Domain member: Require strong (Windows 2000 or later) session key' => {
                :name => 'MACHINE\System\CurrentControlSet\Services\Netlogon\Parameters\RequireStrongKey',
                :policy_type => 'Registry Values',
                :reg_type => '4'
            },
            'Network security: Configure encryption types allowed for Kerberos' => {
                :name => 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters\SupportedEncryptionTypes',
                :policy_type => 'Registry Values',
                 :reg_type => '4'
            },
            'Network security: Allow LocalSystem NULL session fallback' => {
                :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\MSV1_0\allownullsessionfallback',
                :policy_type => 'Registry Values',
                 :reg_type => '4'
            },
            'Domain controller: Allow server operators to schedule tasks' => {
                 :name => 'MACHINE\System\CurrentControlSet\Control\Lsa\SubmitControl',
                 :policy_type => 'Registry Values',
                 :reg_type => '4'
            },
            'Network access: Shares that can be accessed anonymously' => {
                 :name => 'MACHINE\System\CurrentControlSet\Services\LanManServer\Parameters\NullSessionShares',
                 :policy_type => 'Registry Values',
                 :reg_type => '7'
            },
            'Domain controller: Refuse machine account password changes' => {
                 :name => 'MACHINE\System\CurrentControlSet\Services\Netlogon\Parameters\RefusePasswordChange',
                 :policy_type => 'Registry Values',
                 :reg_type => '4'
            },
            'Domain controller: LDAP server signing requirements' => {
                 :name => 'MACHINE\System\CurrentControlSet\Services\NTDS\Parameters\LDAPServerIntegrity',
                 :policy_type => 'Registry Values',
                 :reg_type => '4'
            },
            "MACHINE\\System\\CurrentControlSet\\Control\\Print\\Providers\\LanMan Print Services\\Servers\\AddPrinterDrivers" => {
                :name => "MACHINE\\System\\CurrentControlSet\\Control\\Print\\Providers\\LanMan Print Services\\Servers\\AddPrinterDrivers",
                :policy_type => "Registry Values",
                :reg_type => "4"
            },
            "MACHINE\\System\\CurrentControlSet\\Control\\Session Manager\\Kernel\\ObCaseInsensitive" => {
                :name => "MACHINE\\System\\CurrentControlSet\\Control\\Session Manager\\Kernel\\ObCaseInsensitive",
                :policy_type => "Registry Values",
                :reg_type => "4"
            },
            "MACHINE\\System\\CurrentControlSet\\Control\\Session Manager\\Memory Management\\ClearPageFileAtShutdown" => {
                :name => "MACHINE\\System\\CurrentControlSet\\Control\\Session Manager\\Memory Management\\ClearPageFileAtShutdown",
                :policy_type => "Registry Values",
                :reg_type => "4"
            },
            "MACHINE\\System\\CurrentControlSet\\Control\\Session Manager\\ProtectionMode" => {
                :name => "MACHINE\\System\\CurrentControlSet\\Control\\Session Manager\\ProtectionMode",
                :policy_type => "Registry Values",
                :reg_type => "4"
            },
            "MACHINE\\System\\CurrentControlSet\\Control\\Session Manager\\SubSystems\\optional" => {
                :name => "MACHINE\\System\\CurrentControlSet\\Control\\Session Manager\\SubSystems\\optional",
                :policy_type => "Registry Values",
                :reg_type => "7"
            },
            "MACHINE\\System\\CurrentControlSet\\Services\\LanManServer\\Parameters\\AutoDisconnect" => {
                :name => "MACHINE\\System\\CurrentControlSet\\Services\\LanManServer\\Parameters\\AutoDisconnect",
                :policy_type => "Registry Values",
                :reg_type => "4"
            },
            "MACHINE\\System\\CurrentControlSet\\Services\\LanManServer\\Parameters\\EnableForcedLogOff" => {
                :name => "MACHINE\\System\\CurrentControlSet\\Services\\LanManServer\\Parameters\\EnableForcedLogOff",
                :policy_type => "Registry Values",
                :reg_type => "4"
            },
            "MACHINE\\System\\CurrentControlSet\\Services\\LanManServer\\Parameters\\EnableSecuritySignature" => {
                :name => "MACHINE\\System\\CurrentControlSet\\Services\\LanManServer\\Parameters\\EnableSecuritySignature",
                :policy_type => "Registry Values",
                :reg_type => "4"
            },
            "MACHINE\\System\\CurrentControlSet\\Services\\LanManServer\\Parameters\\RequireSecuritySignature" => {
                :name => "MACHINE\\System\\CurrentControlSet\\Services\\LanManServer\\Parameters\\RequireSecuritySignature",
                :policy_type => "Registry Values",
                :reg_type => "4"
            },
            "MACHINE\\System\\CurrentControlSet\\Services\\LDAP\\LDAPClientIntegrity" => {
                :name => "MACHINE\\System\\CurrentControlSet\\Services\\LDAP\\LDAPClientIntegrity",
                :policy_type => "Registry Values",
                :reg_type => "4"
            }

        }
    end
end
