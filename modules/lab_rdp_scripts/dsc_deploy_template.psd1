@{
    #############################
    # Inject variables for all nodes
    #############################
    AllNodes = 
    @(
        @{        
            
            NodeName                           = "*"
            #define role group names
            BrokerGroupName                    = "${broker_group_name}"
            SessionGroupName                  = "${session_group_name}"
            GatewayGroupName                  = "${gateway_group_name}"
            webGroupName                      = "${web_group_name}"
            #define hosts for each role type
            BrokerHosts                       = @(${broker_hosts})
            SessionHosts                      = @(${session_hosts})
            GatewayHosts                      = @(${gateway_hosts})
            WebHosts                          = @(${web_hosts})
            #define the LoadBalancer configuration details
            BrokerRecordName                  = "${broker_record_name}"
            GatewaysRecordName                = "${gateway_record_name}"
            WebRecordName                     = "${web_record_name}"
            BrokerLbIpAddress                 = "${broker_lb_ip_address}"
            GatewayLbIpAddress                = "${gateway_lb_ip_address}"
            WebLbIpAddress                    = "${web_lb_ip_address}"
            #define the domain details
            DomainName                        = "${domain_name}"
            DomainFqdn                        = "${domain_fqdn}"
            #define the SQL details
            SqlServer                         = "${sql_server}"
            SqlServerInstance                 = "${sql_server_instance}"
            SqlClientShare                    = "sqlclient" 
            #define the GMSA details
            EnableGmsa                        = ${enable_gmsa}  
            brokerGmsaAccountName             = "${broker_gmsa_account_name}"
            #allow plain text passwords for now
            PSDscAllowDomainUser               = $true
            PSDscAllowPlainTextPassword        = $true

            AdminUser                         = "${admin_user}"
            AdminPassword                     = "${admin_password}"             
            [PSCredential] $adminCredential    = New-Object System.Management.Automation.PSCredential(($DomainName + "\" + $AdminUser), ( $AdminPassword | ConvertTo-SecureString -asPlainText -Force ))

            GMSAusername                      = $DomainName + "\" + $brokerGmsaAccountName + "$"
            [PSCredential] $GMSACredential     = New-Object System.Management.Automation.PSCredential($GMSAusername, ( "unusedPassword" | ConvertTo-SecureString -AsPlainText -Force ))

            sqladmin                          = "${sql_admin}"
            sqlPassword                       = "${sql_password}"             
            [PSCredential]$credentialObjectSql = New-Object System.Management.Automation.PSCredential( $sqladmin, ( $sqlPassword | ConvertTo-SecureString -AsPlainText -Force ))
        },

        #Script Node
        @{
            NodeName = 'sc-westus2-ac-1'
            Role     = "Script"
        },

        # BrokerNodes
        @{
            NodeName               = @(${broker_hosts})
            Role                   = "Broker"
            #define the GMSA details
            brokerGmsaRights      = @("Adjust_memory_quotas_for_a_process", "Generate_security_audits", "Log_on_as_a_service", "Replace_a_process_level_token", "Impersonate_a_client_after_authentication", "Bypass_traverse_checking", "Create_global_objects" )
            brokerServiceList     = @('Tssdis', 'RDMS', 'TScPubRPC')
            brokerServiceListFull = @('Remote Desktop Management', 'Remote Desktop Connection Broker', 'RemoteApp and Desktop Connection Management')
        },

        # GatewayNodes
        @{
            NodeName   = @(${gateway_hosts})
            Role       = "Gateway"
            Thumbprint = "${thumbprint}"
        },

        # WebNodes
        @{
            NodeName       = @(${web_hosts})
            Role           = "Web"
            ValidationKey = "${validation_key}"
            DecryptionKey = "${decryption_key}"
            Decryption    = "AES"
            Validation    = "HMACSHA256"
        },

        # SessionNodes
        @{
            NodeName    = @(${session_hosts})
            Role        = "Session"
            collections = @(
                [PSCustomObject]@{
                    name         = "${collection_name}"
                    Description  = "${collection_description}"
                    sessionHosts = @(${session_hosts})
                }
            )            
        }
    )
}    