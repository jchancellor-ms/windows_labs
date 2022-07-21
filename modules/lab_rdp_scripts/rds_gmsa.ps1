#deploy rsat tools

Add-KdsRootKey –EffectiveTime ((get-date).addhours(-10))

New-ADServiceAccount "brokergmsa" -DNSHostName "${gmsahost}.${domainname}" –PrincipalsAllowedToRetrieveManagedPassword "${brokergroup}" -ManagedPasswordIntervalInDays 1


#install account on each broker server
Install-ADServiceAccount -Identity "${brokerserver}"

#reconfigure the broker service to run as the gmsa with a blank password
$secureString = "" | ConvertTo-SecureString -AsPlainText -Force 
$credentialObject = New-Object System.Management.Automation.PSCredential -ArgumentList "brokergmsa$" , $secureString

Set-Service -name "broker" -credential $credentialObject

