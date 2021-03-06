function Invoke-CommandLocalOrRemotely {
	param(
		$scriptBlock,
		$argumentList = @(),
		$session
	)
	
	if($session -ne $null) {
		write-verbose ("Running on computer {0}" -f $session.ComputerName)
		return invoke-command -session $session -argumentList $argumentList -scriptblock $scriptBlock
	}
	else {
		write-verbose "Running locally"
		return $scriptBlock.Invoke($argumentList)
	}
}


$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path -Parent $ScriptPath
$base_directory= Split-Path -Parent (Split-Path -Parent $ScriptPath)
$package_directory = "$base_directory\package"
$build_directory = "$base_directory\build"
$module_directory = "$build_directory\modules"

foreach ($item in Get-ChildItem $module_directory) 
    { Import-Module -Name $module_directory\$item -Force}

$environment = $args[0]
if ($args -eq $null -or $args[0] -eq $null )
{
    Write-Host ("Usage: release_build <env> . Like release_build qa")    
    Exit
}
 Write-Host "Environment: $environment"
[xml]$serverFile = Get-Content $build_directory\servers.$environment.xml
[System.Xml.XmlElement] $root = $serverFile.get_DocumentElement()

$count = $root.ChildNodes.Count;

for ($i=0; $i -lt $count; $i++)
{
        $serverName = $root.ChildNodes[$i].Name    
        $serveruserName = $root.ChildNodes[$i].UserName
        $serverpassword = $root.ChildNodes[$i].Password
        $serverRootPath = $root.ChildNodes[$i].DeployPath    

        Write-Host $serveruserName
        Write-Host $serverpassword
        
        
        $totalServices = $root.ChildNodes[$i].ChildNodes.Count
        $serviceDetails = @{}
        $serviceTypeDetails = @{}
        $userName = @{}
        $password = @{}
       for($j=0;$j -lt $root.ChildNodes[$i].ChildNodes.Count;$j++)
        {
            $serviceDetails[$j]= $root.ChildNodes[$i].ChildNodes[$j].Name   
            $serviceTypeDetails[$j]=$root.ChildNodes[$i].ChildNodes[$j].Type  
            $userName[$j]=$root.ChildNodes[$i].ChildNodes[$j].UserName
            $password[$j]=$root.ChildNodes[$i].ChildNodes[$j].Password
        }       
        Write-Host "Deploying to $serverName at the $serverRootPath"

   
        #Do we need to tranpose configs for distributors and workers???
           
        #Copy packge files to the server - this is the place where its hosted.
        if([string]::IsNullOrEmpty($serverName)){
            $stagePath = "$serverRootPath\$stagePath\Stage"
            
        }
        else{
            $stagePath = $serverRootPath.Replace(":\","$\")
            $stagePath = "\\$serverName\$stagePath\Stage"
        }
        Write-Host "stagePath: $stagePath"
        
        
        if (Test-Path -Path $stagePath)
        {
            Remove-Item $stagePath -Recurse
        }            
        Copy-Item $package_directory -Destination $stagePath -Recurse -Force  
       
       
       
       ##-----------Remote invocation required--------------------#####
        
        $stagePath = "$serverRootPath\Stage"
        $servicePath = "$serverRootPath\Services"
        $BackupPath = "$serverRootPath\Backup"
        if([string]::IsNullOrEmpty($serverName) -or $environment -eq "local"){
            $session = $null
        }
        else{
            $session = New-PSSession -ComputerName $serverName 
        }
        $dateString = (Get-Date).ToShortDateString().Replace("/","_")
        $timeString = (Get-Date).ToLongTimeString().Replace(":","_").Split(" ")[0]
        $backupPathTodayDate = "$BackupPath\$dateString"
        $backupPathTodayDate= "$backupPathTodayDate"+"_"+$timeString
        Write-Host "Taking Backup at $backupPathTodayDate"
        #Make a backup
        Invoke-CommandLocalOrRemotely -session $session -argumentList ($backupPathTodayDate,$servicePath) -scriptBlock{
            Param($backupPathTodayDate, $destinationService_Path)
            if (Test-Path -Path $backupPathTodayDate)
            {
                Remove-Item $backupPathTodayDate -Recurse 
            }
            if (Test-Path -Path $destinationService_Path )
            {
                Copy-Item $destinationService_Path -Destination $backupPathTodayDate -Recurse -Force
            }
        }

        Write-Host "Stopping and uninstalling installed services"
        #Stop and uninstall 
        Invoke-CommandLocalOrRemotely -session $session -argumentList ($serviceDetails,$serviceTypeDetails,$servicePath) -scriptBlock{
            Param($serviceDetails, $serviceTypeDetails, $servicePath)
            for($i=0;$i -lt $serviceDetails.Count;$i++)
            {
                Write-Host "Installing Service $servicePath"
                $serviceName=$serviceDetails[$i]
                $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                if ($service -ne $null)
                {
                    if ($service.Status -ne "Stopped")
                    {
                        Stop-Service $serviceName
                        $service.WaitForStatus('Stopped')
                    }
                    $servicetoUninstall = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'"
                    Write-Host $serviceName      
                    if ($servicetoUninstall -ne $null)
					{
						{$servicetoUninstall.delete() > $null}
						if (!$?)
						{
							Write-Error "Error Uninstalling service $servicetoUninstall"
							Exit 1
						}			
					}
						
                }                
            } 
        }
        Write-Host "Copy to service location $servicePath"
        Invoke-CommandLocalOrRemotely -session $session -argumentList ($serviceDetails,$serviceTypeDetails,$servicePath, $stagePath) -scriptBlock{
            Param($serviceDetails, $serviceTypeDetails, $servicePath,$stagePath)
            for($i=0;$i -lt $serviceDetails.Count;$i++)
            {
                $serviceName=$serviceDetails[$i]
                if (Test-Path -Path $servicePath\$serviceName)
                {
                    Remove-Item $servicePath\$serviceName -Recurse 
                }     
				if (!$?)
                {
                    Write-Error "Error Occured when removing services from the the $servicePath\$serviceName"
                    Exit 1
                }				
                Copy-Item $stagePath\$serviceName -Destination $servicePath\$serviceName -Recurse -Force   
				if (!$?)
                {
                    Write-Error "Error Occured when copying services to the service path $servicePath\$serviceName"
                    Exit 1
                }				
            }
        }
      #  Disconnect-PSSession -session $session > $null

        #Install service as the service user 

        Write-Host "Installing services in $environment"        
       # $serverEncrypedpassword = ConvertTo-SecureString -String $serverpassword -AsPlainText -Force
       # $mycreds = New-Object System.Management.Automation.PSCredential ($serveruserName, $serverEncrypedpassword )
       # $session = New-PSSession -ComputerName $serverName -Credential $mycreds

        #install services - this will depend on roles
        Invoke-CommandLocalOrRemotely -session $session -argumentList ($serviceDetails,$serviceTypeDetails,$servicePath, $stagePath, $serveruserName, $serverpassword, $userName, $password, $environment, $module_directory) -scriptBlock{
            Param($serviceDetails, $serviceTypeDetails, $servicePath,$stagePath,$serveruserName, $serverpassword, $userName, $password, $environment, $module_directory)
           
            for($i=0;$i -lt $serviceDetails.Count;$i++)
            { 
                
                #Installing services
                $serviceName = $serviceDetails[$i]                
                
                if ($userName -eq $null -or $password -eq $null-or $userName[$i] -eq $null -or $password[$i] -eq $null)
                {                 
                    $currentUserName=$serveruserName
                    $currentPassword=$serverpassword                    
                }
                else
                {                    
                    $currentUserName=$userName[$i]
                    $currentPassword=$password[$i]
                }
                $authDetails = ""              
                if ($currentUserName -ne $null -and $currentPassword -ne $null)
                {
                    $authDetails = " /username:""$currentUserName"" /password:""$currentPassword"" "
                }               
                $exeName = "$servicePath\$serviceName\NServicebus.Host.exe"  
                $serviceType = $serviceTypeDetails[$i]  
                #need to decide which files to copy over for differnet modes.
                if(Test-Path -Path "$servicePath\$serviceName\$serviceType.dll.config")
                {
                    Write-Host "final env transform.  copying $servicePath\$serviceName\$serviceType.dll.config -Destination $servicePath\$serviceName\$serviceName.dll.config -Force"
                    Copy-Item "$servicePath\$serviceName\$serviceType.dll.config" -Destination "$servicePath\$serviceName\$serviceName.dll.config" -Force
                }
                else
                {
                    Write-Host "no override config found at $servicePath\$serviceName\$serviceType.dll.config"
                }
                Write-Host "Uninstalling service $exeName" 
                $arguments = "/uninstall"
                Start-Process $exeName $arguments -Wait
                Write-Host "Installing service as a $serviceType" 
                $arguments = "NServiceBus.Production NServiceBus.Distributor $authDetails /install"     
                if ($serviceTypeDetails[$i] -eq "Distributor")
                {

                    $expressionToExecute = "$servicePath\$serviceName\NServicebus.Host.exe NServiceBus.Production NServiceBus.Distributor $authDetails /install "
                    $arguments = "NServiceBus.Production NServiceBus.Distributor $authDetails /install"             
                }
                elseif ($serviceTypeDetails[$i] -eq "Worker")
                {
                    $transformPath = "$servicePath\$serviceName"
                    $expressionToExecute = "$servicePath\$serviceName\NServicebus.Host.exe NServiceBus.Production NServiceBus.Worker $authDetails /install "             
                    $arguments = "NServiceBus.Production NServiceBus.Worker $authDetails /install"             
                }
                elseif ($serviceTypeDetails[$i] -eq "Independent")
                {
                    $expressionToExecute = "$servicePath\$serviceName\NServicebus.Host.exe NServiceBus.Production $authDetails /install "          
                    $arguments = "NServiceBus.Production  $authDetails /install"                
                }
                else
                {
                    continue;
                }
                Write-Host $exeName
                Write-Host $arguments
                Start-Process $exeName $arguments -Wait
				if (!$?)
                {
                    Write-Error "Error Occured when installing the service"
                    Exit 1
                }
                
            }
        }
	#	Disconnect-PSSession -session $session > $null
		if([string]::IsNullOrEmpty($serverName) -or $environment -eq "local"){
            $session = $null
        }
        else{
            $session = New-PSSession -ComputerName $serverName 
        }
		#start services
        Invoke-CommandLocalOrRemotely -session $session -argumentList ($serviceDetails,$serviceTypeDetails,$servicePath, $stagePath) -scriptBlock{
            Param($serviceDetails, $serviceTypeDetails, $servicePath,$stagePath)
            for($i=0;$i -lt $serviceDetails.Count;$i++)
            {
                $serviceName = $serviceDetails[$i]
                Start-Service $serviceName
				if (!$?)
                {
                    Write-Error "Error Occured when starting the service"
                    Exit 1
                }
			}
        }
        if($session -ne $null){
            Disconnect-PSSession -session $session > $null
        }
}












