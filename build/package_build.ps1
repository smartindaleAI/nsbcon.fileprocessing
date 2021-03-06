#Input Parameters


$sln_name = "NsbCon.sln"


$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path -Parent $ScriptPath
$base_directory= Split-Path -Parent (Split-Path -Parent $ScriptPath)
Write-Host $base_directory
$build_directory = "$base_directory\build"
$package_directory = "$base_directory\package" 
$sourcepath= "$base_directory\src"

$module_directory = "$build_directory\modules"
foreach ($item in Get-ChildItem $module_directory) 
    { Import-Module -Name $module_directory\$item}


#validate args
if ($args -eq $null -or $args[0] -eq $null -or $args[1] -eq $null)
   {
        Write-Host ("Usage: package_build <env> <configuration>. Like package_build qa debug")    
        Exit
    }

$configuration = $args[1]
$environment = $args[0]

	

#Call msbuild - will be later on moved to psake and dependecies   
$buildSucceeded = Invoke-MsBuild -Path $base_directory\$sln_name -Params "/target:Clean;Build /property:Configuration=$configuration"


if ($buildSucceeded='True')
    {  
        Write-Host "Build completed successfully." 
        #Exit-PSSession
    }
else
	{ Write-Host "Build failed. Check the build log file for errors."
		Exit 1	
	}


#Need to run tests -- later
Write-Host "-projectPath  $sourcepath  -configuration $configuration -environment  $environment"
Transform-ConfigFileForProject -projectPath  $sourcepath  -configuration $configuration -environment  $environment  -recurse -ea Stop


#Deployment 1 - Package all the services after successful build

[string] $include =  "\.Service$|\.Services$|\.Endpoint$|\.Handlers$|\.Portal$|\.Web$|\.WebApi$"

$items = get-childitem -path $sourcepath | where {$_ -match $include}
#$items = $items | Where { $_ -notmatch $exclude }

Write-Host  ("Copying to the package folder")
$items | foreach{
    Write-Host $_
    $targetDirectory = "$package_directory\$_\"
    $sourceDirectory = "$sourcepath\$_\bin\$configuration\"
    if(!(Test-Path -Path $sourceDirectory)){
        $sourceDirectory = "$sourcepath\$_"
    }

    $envConfigDirectory = "$package_directory\$_\Config\$environment\"
    if (Test-Path -Path $targetDirectory)
        {
            Remove-Item $targetDirectory -Recurse 
        }

    
    
    Copy-Item $sourceDirectory $targetDirectory -Recurse -Force 


    
	Copy-Item $base_directory\lib\*.* $targetDirectory\

   
    if (Test-Path -Path $envConfigDirectory)
        {
            Write-Host("writing from $envConfigDirectory*.* to $targetDirectory")
            Copy-Item "$envConfigDirectory*.*" $targetDirectory -Recurse #-Force
        }
    else{
         Write-Host("no environmental assets found at $envConfigDirectory*.*")
    }
 

    
	
    #Copy applications.config and connectionstrings.config etc based on the configuration from the directories
 # $appdestination= "$targetDirectory\ApplicationSettings.config"
  # $conndestination =  "$targetDirectory\ConnectionStrings.config"    
   #$appsource = "$base_Directory\Configuration\$environment\ApplicationSettings.config" 
   
  # $connsource = "$base_Directory\Configuration\$environment\ConnectionStrings.config" 

#   Copy-Item $appsource $appdestination -Recurse -Force
 #  Copy-Item $connsource $conndestination -Recurse -Force


    }
    

