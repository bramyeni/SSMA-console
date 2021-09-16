
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Originally Created by Bram pahlawanto on 14-OCT-2020
# $Id: RunSSMA.ps1 56 2021-09-16 16:42:51Z bpahlawa $
# $Date: 2021-09-17 00:42:51 +0800 (Fri, 17 Sep 2021) $
# $Revision: 56 $
# $Author: bpahlawa $
# 

<#

.PARAMETER Mode
Choose SSMA mode
all         = Perform SSMA Assessment and conversion
assess      = Perform SSMA Assessment only (default)
convert     = Perform SSMA Conversion only
gensql      = Generate sql script from source database only
querydb     = Query source database
lookupdb    = Query source database and check whether the objects within objectlist.ini matches
listobjects = Generate group of objecs from a file pointed by Parameter ListObjFilename (default=objects.txt)
convertsql  = Perform SSMA save as script which also rely on parameter ConvertMode and SQLQuery

.PARAMETER SQLQuery
This parameter can be a query or a file contains list of queries

.PARAMETER OracleConnection
Source oracle connection name by default source_oraservice

.PARAMETER ListObjFilename
see Parameter Mode 

.PARAMETER ConvertMode
apply only when Parameter convertsql is selected
list of ConvertMode are:
sqlcmdtofile      = Convert Query on SQLquery will be spooled to an output file
sqlfilestofile    = Convert Query stored in *.SQL Files will be spooled to an output file
sqlcmdtoconsole   = Convert Query on SQLQuery will be displayed on console
sqlfilestofiles   = Convert Query stored in *.SQL Files will be spooled to output files *.SQL
sqlfilestoconsole = Convert Query stored in *.SQL files will be displayed on console

.DESCRIPTION
Run SSMA console with configurable parameters

.EXAMPLE
.\runSSMA.ps1 -Mode all

.EXAMPLE
.\runSSMA.ps1 -Mode querydb -SQLQuery "select table_name from dba_tables where owner='THEOWNER'"

.SYNOPSIS
Run SSMA console with configurable parameters through command line
it can perform automated assessments and conversions for multiple databases



#>

param (
    [string]$Mode = "assess", 
    [String]$OracleConnection = "source_oraservice",
    [String]$SQLQuery,
    [String]$ListObjFilename = "objects.txt",
    [String]$ConvertMode,
    [String]$SpoolFile
)

$Global:ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
cd $Global:ScriptDir
$global:config="config.ini"
$global:objconfig="objectlist.ini"
$global:storeobjects="allobjects"
$global:SSMAconsole="C:\Program` Files\Microsoft` SQL` Server` Migration` Assistant` for` Oracle\bin\SSMAForOracleConsole.exe"
$global:SSMADir=(split-path -path $global:SSMAconsole)
$global:O2SSConsoleScriptSchema="$($global:SSMADir)\..\Schemas\O2SSConsoleScriptSchema.xsd"
$global:O2SSConsoleScriptServersSchema="$($global:SSMADir)\..\Schemas\O2SSConsoleScriptServersSchema.xsd"
$global:ConsoleScriptVariablesSchema="$($global:SSMADir)\..\Schemas\ConsoleScriptVariablesSchema.xsd"
$global:instantclientdir="c:\instantclient"
$global:OMDA="$($global:instantclientdir)\odp.net\managed\common\Oracle.ManagedDataAccess.dll"

$global:VARSXML="Variables"
$global:AssessXML="Assessment"
$global:ConnXML="Connection"
$global:ConversionXML="ConvertAndMigrate"
$global:ConvertSQLXML="ConvertSQLCommand"
$global:TargetDB=""
$global:targetplatform=""
$global:xmloutput=""

$global:objectlist=$null
$global:tgtschema=$null
$global:synctargetonerror=$null
$global:refreshdbonerror=$null
$global:csvfile="dboutput.csv"

Function Check-FileAndDir
{
  param ([String]$filedir,
         [Bool]$CreateIt=$False
        )

    if ((Test-path -path "$filedir") -eq $False) 
    {  
       if ($createit)
       {
          if (Test-path -path "$filedir" -PathType container)
          {
             write-host "Creating Directory $($filedir) ..."
             try {
                  New-item "$filedir" -itemtype "directory" -ErrorAction Stop
             }
             catch {
                  Write-Output $PSItem.toString()
                  exit 1
             }

          }
          else
          {
             write-host "Creating File $($filedir) ..."
             try {
                  new-item "$filedir" -ItemType "file" -ErrorAction stop
             }
             catch {
                  Write-Output $PSItem.toString()
                  exit 1
             }
          }
       }
       else
       {
          write-host "File or directory $($filedir) doesnt exist.."; 
          exit 1
       } 
    }



}

function Get-IniContent ($filePath)
{
    $ini = @{}
   
    switch -regex -file $FilePath
    {
        “^\[(.+)\]” # Section
        {
            $section = $matches[1]
            $ini[$section] = @{}
            $CommentCount = 0
        }
        “^(;.*)$” # Comment
        {
            $value = $matches[1]
            $CommentCount = $CommentCount + 1
            $name = “Comment” + $CommentCount
            $ini[$section][$name] = $value
        }
        “(.+?)\s*=(.*)” # Key
        {
            $name,$value = $matches[1..2]
            $ini[$section][$name] = $value
        }
    }
    return $ini
}


$global:initcontent=get-inicontent("$global:config")

Function Create-SQL-Conversion()
{
param (
    [Parameter(Mandatory=$true)]
    [String]$ConvertMode = "sqlcmdtofile",
    [string]$SQlQuery
)

$sqlconversionoutput = @"
 <script-commands>
    <create-new-project project-folder="`$project_folder$"
                        project-name="`$project_name$"
                        project-type="`$project_type$"
                        overwrite-if-exists="`$project_overwrite$" />
    <connect-source-database server="$OracleConnection">
    OBJECTTOCOLLECT
    </connect-source-database>

    TARGETDB


    CONVERTSQL

    <!-- Save project -->
    <save-project />
    <!-- Close project -->
    <close-project />
  </script-commands>
</ssma-script-file>
"@  

$sqlconversionoutput = $sqlconversionoutput -replace "TARGETDB",$global:TargetDB

$sqlconversionoutput = $sqlconversionoutput -replace "OBJECTTOCOLLECT",(Select-ObjectToCollect -NTHDB "db1")


switch -exact ($ConvertMode)
{
   'sqlcmdtofile'  
   {
 
      $convertedsql=@"
 <convert-sql-statement context="`$OracleSchemaName$"
                           destination="file"
                           write-summary-report-to="`$SummaryReports$"
                           verbose="true"
                           report-errors="true"
                           conversion-report-folder="`$ConvertARReportsFolder$"
                           conversion-report-overwrite="true"
                           write-converted-sql-to="`$ConvertSQLReports$\ConvertedResult.sql"
                           sql="$SQLQuery;" />

"@

   }
   'sqlfilestofile'
   {
      $convertedsql=@"
<convert-sql-statement context="`$OracleSchemaName$"
                           destination="file"
                           write-summary-report-to="`$SummaryReports$"
                           verbose="true"
                           report-errors="true"
                           conversion-report-folder="`$ConvertARReportsFolder$"
                           conversion-report-overwrite="true"
                           write-converted-sql-to="`$ConvertSQLReports$\ConvertedResult.sql"
                           sql-files="`$SourceSQLFiles$\*.sql" />

"@
       

   }
   'sqlcmdtoconsole'
   {
      $convertedsql="<convert-sql-statement context=`"`$OracleSchemaName$`" sql=`"`$SQLQuery;`" />"

   }
   'sqlfilestoconsole'
   {
      $convertedsql="<convert-sql-statement context=`"`$OracleSchemaName$`" sql-files=`"`$SourceSQLFiles$\*.sql`" />"
   }
   'sqlfilestofiles'
   {
      $convertedsql=@"
<convert-sql-statement context="`$OracleSchemaName$"
                           destination="file"
                           write-summary-report-to="`$SummaryReports$"
                           verbose="true"
                           report-errors="true"
                           conversion-report-folder="`$ConvertARReportsFolder$"
                           conversion-report-overwrite="true"
                           write-converted-sql-to="`$ConvertSQLReports$"
                           sql-files="$SourceSQLFiles$\*.sql" />
"@
   }
}
   $sqlconversionoutput=$sqlconversionoutput -replace "CONVERTSQL",$convertedsql
 
   $FileConvert = "$global:xmloutput\$global:ConvertSQLXML.xml"

   $sqlconversionoutput = "<?xml version=`"1.0`" encoding=`"utf-8`"?>
<ssma-script-file xmlns:xsi=`"http://www.w3.org/2001/XMLSchema-instance`" xsi:noNamespaceSchemaLocation=`"$($global:O2SSConsoleScriptSchema)`">
   $(create-config -section "conversion")
   $sqlconversionoutput
   " | out-file -FilePath $FileConvert -Encoding ascii -force
}


Function Create-Conversion()
{
param (
    [Parameter(Mandatory=$true)]
    [string]$NTHDB,
    [boolean]$RefreshDatabase = $true,
    [boolean]$ConvertSchema = $true,
    [boolean]$SyncTarget = $true,
    [boolean]$SaveScript =$true,
    [boolean]$DataMigration = $true

)

$conversionoutput = @"
 <script-commands>
    <create-new-project project-folder="`$project_folder$"
                        project-name="`$project_name$"
                        project-type="`$project_type$"
                        overwrite-if-exists="`$project_overwrite$" />
    <connect-source-database server="$OracleConnection">
    OBJECTTOCOLLECT
    </connect-source-database>

    TARGETDB

    <map-schema source-schema="`$OracleSchemaName$"
                sql-server-schema="[`$DatabaseName$].$($global:tgtschema)" />

    TYPEMAPPING

    REFRESHDATABASE

    CONVERTSCHEMA

    SYNCTARGET 

    SAVEASSCRIPT

    DATAMIGRATION
    <!-- Save project -->
    <save-project />
    <!-- Close project -->
    <close-project />
  </script-commands>
</ssma-script-file>
"@  

$conversionoutput = $conversionoutput -replace "TARGETDB",$global:TargetDB

$conversionoutput = $conversionoutput -replace "OBJECTTOCOLLECT",(Select-ObjectToCollect -NTHDB "$NTHDB")



   if ($global:initcontent.containskey("$NTHDB"))
   {
      $object=$global:initcontent["$NTHDB"]["object"]
      if ($object -eq $null) {  $object=$global:initcontent["alldb"]["object"] }
      $objecttype=$global:initcontent["$NTHDB"]["objecttype"]
      if ($objecttype -eq $null) { $objecttype=$global:initcontent["alldb"]["objecttype"] }

   }
   else
   {
      $object=$global:initcontent["alldb"]["object"]
      $objecttype=$global:initcontent["alldb"]["objecttype"]
     
   }


   
   if ($object -eq "all" -or $object -eq 'single')
   {
       if ($Refreshdatabase)
       {
         $conversionoutput = $conversionoutput -replace "REFRESHDATABASE",(Select-RefreshDatabase -Object $object -NTHDB $NTHDB)
       }
       else
       {
         $conversionoutput = $conversionoutput -replace "REFRESHDATABASE",""
       }
       if ($ConvertSchema)
       {
         $conversionoutput = $conversionoutput -replace "CONVERTSCHEMA",(Select-ConvertSchema -Object $object -NTHDB $NTHDB)
       }
       else
       {
         $conversionoutput = $conversionoutput -replace "CONVERTSCHEMA",""
       }
       if ($SyncTarget)
       {
         $conversionoutput = $conversionoutput -replace "SYNCTARGET",(Select-SyncTarget -Object $object -NTHDB $NTHDB)
       }
       else
       {
         $conversionoutput = $conversionoutput -replace "SYNCTARGET",""
       }
       if ($DataMigration)
       {
         $conversionoutput = $conversionoutput -replace "DATAMIGRATION",(Select-DataMigration -Object $object -NTHDB $NTHDB)
       }
       else
       {
         $conversionoutput = $conversionoutput -replace "DATAMIGRATION",""
       }

       if ($SaveScript)
       {
         $conversionoutput = $conversionoutput -replace "SAVEASSCRIPT",(Select-SaveAsScript -Object $object -NTHDB $NTHDB)
       }
       else
       {
         $conversionoutput = $conversionoutput -replace "SAVEASSCRIPT",""
       }

       $conversionoutput = $conversionoutput -replace "TYPEMAPPING",(Select-TypeMapping -Object $object -NTHDB $NTHDB)

   }
   else
   {
      if ($Refreshdatabase)
       {
          $conversionoutput = $conversionoutput -replace "REFRESHDATABASE",(Select-RefreshDatabase -Object "category" -ObjectType $objecttype -NTHDB $NTHDB)
       }
       else
       {
         $conversionoutput = $conversionoutput -replace "REFRESHDATABASE",""
       }
       if ($ConvertSchema)
       {
          $conversionoutput = $conversionoutput -replace "CONVERTSCHEMA",(Select-ConvertSchema -Object "category" -ObjectType $objecttype -NTHDB $NTHDB)
       }
       else
       {
         $conversionoutput = $conversionoutput -replace "CONVERTSCHEMA",""
       }
       if ($SyncTarget)
       {
         $conversionoutput = $conversionoutput -replace "SYNCTARGET",(Select-SyncTarget -Object "category" -ObjectType $objecttype -NTHDB $NTHDB)
       }
       else
       {
         $conversionoutput = $conversionoutput -replace "SYNCTARGET",""
       }
       if ($DataMigration)
       {
         $conversionoutput = $conversionoutput -replace "DATAMIGRATION",(Select-DataMigration -Object "category" -ObjectType $objecttype -NTHDB $NTHDB)
       }
       else
       {
         $conversionoutput = $conversionoutput -replace "DATAMIGRATION",""
       }

       if ($SaveScript)
       {
         $conversionoutput = $conversionoutput -replace "SAVEASSCRIPT",(Select-SaveAsScript -Object "category" -ObjectType $objecttype -NTHDB $NTHDB)
       }
       else
       {
         $conversionoutput = $conversionoutput -replace "SAVEASSCRIPT",""
       }       
       $conversionoutput = $conversionoutput -replace "TYPEMAPPING",(Select-TypeMapping -Object "category" -ObjectType $objecttype -NTHDB $NTHDB)
   }

   $FileConvert = "$global:xmloutput\$global:ConversionXML$NTHDB.xml"

   $conversionoutput = "<?xml version=`"1.0`" encoding=`"utf-8`"?>
   <ssma-script-file xmlns:xsi=`"http://www.w3.org/2001/XMLSchema-instance`" xsi:noNamespaceSchemaLocation=`"$($global:O2SSConsoleScriptSchema)`">
   $(create-config -section "conversion")
   $conversionoutput
   " | out-file -FilePath $FileConvert -Encoding ascii -force -ErrorAction stop
}


Function Select-TypeMapping()
{

param (
    [Parameter(Mandatory=$true)]
    [string]$Object,
    [String]$ObjectName,
    [String]$ObjectType,
    [Parameter(Mandatory=$true)]
    [String]$NTHDB
)

$objecttypemapping = @"
    #OBJMAPPING#
    
    <!-- Example 2: Set object type mapping with parameters, need to add suffix '@' sign with number of parameters in type-id
         Attributes start/end/value in type parameter are optional -->
    <!--<set-object-type-mapping type-mapping-schema="Columns type mapping" source-type-id="LONG RAW@1" target-type-id="VARBINARY@1" object-name="$OracleSchemaName$.Tables" object-type="category">
      <source-type-param start="4001" end="6000" />
      <target-type-param value="8000" />
    </set-object-type-mapping>-->
"@

$TextInfo = (Get-Culture).TextInfo



    if ($global:initcontent.containskey("$NTHDB"))
    {
        $objecttypemapping=$global:initcontent["$NTHDB"]["objecttypemapping"] 
        $sourcetypeid=$global:initcontent["$NTHDB"]["sourcetypeid"]
        $targettypeid=$global:initcontent["$NTHDB"]["targettypeid"]
        $typemapping=$global:initcontent["$NTHDB"]["typemapping"]
        if ($objecttypemapping -eq $null -or $sourcetypeid -eq $null -or $targettypeid -eq $null -or $typemapping -eq $null)
        {
            $objecttypemapping=$global:initcontent["alldb"]["objecttypemapping"]
            $sourcetypeid=$global:initcontent["alldb"]["sourcetypeid"]
            $targettypeid=$global:initcontent["alldb"]["targettypeid"]
            $typemapping=$global:initcontent["alldb"]["typemapping"]
            if ($objecttypemapping -eq $null -or $sourcetypeid -eq $null -or $targettypeid -eq $null -or $typemapping -eq $null)
            {
               
                return $null
            }
        }
    

        if ($typemapping -eq "object" )
        {
           $settypemapping="<set-object-type-mapping"
        }
        else
        {
           $settypemapping="<set-project-type-mapping"
        }

    }
    
       



switch -exact ($object)
{
   'category'
    {
        $objectcat=$objecttype.split(',')

        for ($i=0;$i -lt $objectcat.count;$i++)
        {
            $categoryobjmapping=$categoryobjmapping + "$settypemapping type-mapping-schema=$objecttypemapping source-type-id=`"$sourcetypeid`" target-type-id=`"$targettypeid`" object-name=`"`$OracleSchemaName$.$($TextInfo.ToTitleCase($objectcat[$i]))`" object-type=`"category`" />`n"
        }

   
        return $categoryobjmapping
    } 
   'single'
   {

        $global:objectlist=get-inicontent("$global:objconfig")
      
        if ($global:objectlist -ne $null)
        {
            if ($NTHDB -ne $null -and $global:objectlist.Contains("$NTHDB") )
            {
                $objs=$global:objectlist["$NTHDB"]["objecttype"]
            }
            else
            {
                $objs=$global:objectlist["alldb"]["objecttype"]
            }
        
            $objecttypes=$objs.split(",")
        

            for ($i=0;$i -lt $objecttypes.count;$i++)
            {
                if ($NTHDB -ne $null -and $global:objectlist.Contains("$NTHDB"))
                {
                    $lists=$global:objectlist["$NTHDB"][$objecttypes[$i]]
                }
                else
                {
                    $lists=$global:objectlist["alldb"][$objecttypes[$i]]
                }
          
               $objectlist=$lists.split(",")
               for ($j=0;$j -lt $objectlist.count;$j++)
               {
                    $singleobject=$singleobject + "$settypemapping type-mapping-schema=$objecttypemapping source-type-id=`"$sourcetypeid`" target-type-id=`"$targettypeid`" object-name=`"`$OracleSchemaName$.$($objectlist[$j] -replace "\`$","`$`$`$`$`$`$`$")`" object-type=`"$($TextInfo.ToTitleCase($objecttypes[$i]))`" />`n"
               }
             }
       } 
    if ($singleobject.contains("#OBJMAPPING#"))
    {
        return $null
    }
    else
    {   
        return $singleobject
    }

   }

}
  return $null
}


Function Get-DBConfigParam()
{
param (
    [Parameter(Mandatory=$true)]
    [string]$NTHDB,
    [Parameter(Mandatory=$true)]
    [string]$Key,
    [String]$Suffix

)



    if ($global:initcontent.containsKey("$NTHDB"))
    {
        if ($global:initcontent["$NTHDB"].containskey("$KEY"))
        {
            return $global:initcontent["$NTHDB"]["$KEY"]
        }
        else
        {
            return "$($global:initcontent["alldb"]["$KEY"])$($Suffix)"
        }
    }
    else
    {
        return "$($global:initcontent["alldb"]["$KEY"])$($Suffix)"
    }

}




Function Create-Conn()
{
param (
    [Parameter(Mandatory=$true)]
    [string]$TargetType,
    [Parameter(Mandatory=$true)]
    [string]$NTHDB
)

$onpremwinauth = @"
<sql-server name="target_onpremwinauth">
    <windows-authentication>
      <server value="`$DBServerName$" />
      <database value="`$DatabaseName$" />
      <encrypt value="true" />
      <trust-server-certificate value="true" />
    </windows-authentication>
  </sql-server>
"@

$onpremsqlauth = @"

  <sql-server name="target_onpremsqlauth">
    <sql-server-authentication>
      <server value="`$DBServerName$" />
      <database value="`$DatabaseName$" />
      <user-id value="`$DBUserID$" />
      <password value="`$DBPwd$" />
      <encrypt value="true" />
      <trust-server-certificate value="true" />
    </sql-server-authentication>
  </sql-server>
"@

$azuresqldb = @"

  <sql-server name="target_azuresqlauth">
    <sql-server-authentication>
      <server value="`$DBServerName$" />
      <database value="`$DatabaseName$" />
      <user-id value="`$DBUserID$" />
      <password value="`$DBPwd$" />
      <encrypt value="true" />
      <trust-server-certificate value="true" />
    </sql-server-authentication>
  </sql-server>
"@

$azuresqlmi = @"
  <sql-azure-mi name ="target_azure_mi">
    <ad-integrated-authentication>
      <server value ="`$DBServerName$" />
      <database value ="`$DatabaseName$" />
    </ad-integrated-authentication>
  </sql-azure-mi>
"@

$azuresynapse = @"
  <sql-azure-dw name ="target_azure_dw">
    <sql-server-authentication>
      <server value ="`$DBServerName$" />
      <database value ="`$DatabaseName$" />
      <user-id value ="`$DBUserID$" />
      <password value="`$DBPwd$" />
    </sql-server-authentication>
  </sql-azure-dw>
"@



$header=@"
<?xml version="1.0" encoding="utf-8"?>
<servers xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="$($global:O2SSConsoleScriptServersSchema)">
"@

$oracleconn=@"
  <oracle name="source_oradb">
    <standard-mode>
      <connection-provider value ="OracleClient" />
      <host value="`$OracleHostName$" />
      <port value="`$OraclePort$" />
      <instance value="`$OracleInstance$" />
      <user-id value="`$OracleUserName$" />
      <password value="`$OraclePassword$" />
    </standard-mode>
  </oracle>

 <oracle name="source_orasid">
    <connection-string-mode>
      <connection-provider value ="OracleClient" />
      <custom-connection-string value="Data Source=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=`$OracleHostName$)(PORT=`$OraclePort$))(CONNECT_DATA=(SID=`$OracleInstance$)));User ID=`$OracleUserName$;Password=`$OraclePassword$" />
    </connection-string-mode>
  </oracle>

 <oracle name="source_oraservice">
    <connection-string-mode>
      <connection-provider value ="OracleClient" />
      <custom-connection-string value="Data Source=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=`$OracleHostName$)(PORT=`$OraclePort$))(CONNECT_DATA=(SERVICE_NAME=`$OracleInstance$)));User ID=`$OracleUserName$;Password=`$OraclePassword$" />
    </connection-string-mode>
  </oracle>
</servers>
"@


$FileConn = "$global:xmloutput\$global:ConnXML$NTHDB.xml"


$header | out-file -FilePath $FileConn -Encoding ascii -force

switch -exact ($TargetType)
{
    'onpremwinauth' 
   {
      $onpremwinauth | out-file -FilePath $FileConn -Encoding ascii -force -append
      $global:TARGETDB="<connect-target-database server=`"target_onpremwinauth`" />"
   }
    'onpremsqlauth'
   {
      $onpremsqlauth | out-file -FilePath $FileConn -Encoding ascii -force -append
      $global:TARGETDB="<connect-target-database server=`"target_onpremsqlauth`" />"
   }
    'azuresqldb'
   {
      $azuresqldb | out-file -FilePath $FileConn -Encoding ascii -force -append
      $global:TARGETDB="<connect-target-database server=`"target_azuresqlauth`" />"
   }
    'azuresqlmi'
   {
      $azuresqlmi | out-file -FilePath $FileConn -Encoding ascii -force -append
      $global:TARGETDB="<connect-target-database server=`"target_azure_mi`" />"
   }
    'azuresynapse'
   {
      $azuresynapse | out-file -FilePath $FileConn -Encoding ascii -force -append
      $global:TARGETDB="<connect-target-database server=`"target_azure_dw`" />"
   }
   }
   $oracleconn | out-file -FilePath $FileConn -Encoding ascii -force -append
    
}

Function Create-Config()
{
param (
    [Parameter(Mandatory=$true)]
    [string]$section
)

$configs = @"
<config>
    <output-providers>
      #HEADERSECTION#
      <upgrade-project action="#UPGRADEPROJECT#" />
      <user-input-popup mode="#USERINPUTPOPUP#" />
      <progress-reporting enable="#ENABLEPROGRESSREPORTING#"
                          report-messages="#REPORTMESSAGE#"
                          report-progress="#REPORTPROGRESS#" />
      <prerequisites strict-mode="#PREREQSTRICTMODE#" />
      <log-verbosity level="#LOGVERBOSITY#" />

      <!-- Override encrypted password in protected storage with script file password
           Default option: "false" - Order of search: 1) Protected storage 2) Script File / Server Connection File 3) Prompt User
                           "true"  - Order of search: 1) Script File / Server Connection File 2) Prompt User -->
      <!--<encrypted-password override="true" />-->

    </output-providers>
  </config>
"@

switch -exact ($Section)
{
   'assessment'
   {
      $headerconfig=@"
      <output-window suppress-messages="#SUPPRESSMESSAGE#"
                     destination="file"
                     file-name="`$AssessmentReports$"	/>
"@
      
   }
   'conversion'
   {

       $headerconfig=@"
       <output-window suppress-messages="#SUPPRESSMESSAGE#"
                     destination="file"
                     file-name="`$ConvertARReportsFolder$"	/>
       <data-migration-connection source-server="$OracleConnection"
                                 target-server="TARGETDB" />
       <reconnect-manager on-source-reconnect="reconnect-to-last-used-server"
                             on-target-reconnect="generate-an-error" />
                             <object-overwrite action="skip" />
"@
    if ($global:targetdb -match "^.*=`"(target_[a-z_]+)`" .*")
    {
        $headerconfig = $headerconfig -replace "TARGETDB",$Matches[1]
    }
    else
    {
        $headerconfig=@"
       <output-window suppress-messages="#SUPPRESSMESSAGE#"
                     destination="file"
                     file-name="`$ConvertARReportsFolder$"	/>
       <reconnect-manager on-source-reconnect="reconnect-to-last-used-server"
                             on-target-reconnect="generate-an-error" />
                             <object-overwrite action="skip" />
"@
    }

    

   }
   'sqlconversion'
   {

     $headerconfig=@"
     <output-window suppress-messages="#SUPPRESSMESSAGE#"
                     destination="file"
                     file-name="`$ConvertARReportsFolder$"	/>
"@
   }
}

$configs = $configs -replace "#HEADERSECTION#",$headerconfig

$configs = $configs -replace "#SUPPRESSMESSAGE#",$global:initcontent[$section]["SUPPRESSMESSAGE"]
$configs = $configs -replace "#REPORTFOLDER#",$global:initcontent[$section]["REPORTFOLDER"]

$configs = $configs -replace "#ENABLEPROGRESSREPORTING#", $global:initcontent[$section]["ENABLEPROGRESSREPORTING"]
$configs = $configs -replace "#REPORTMESSAGE#", $global:initcontent[$section]["REPORTMESSAGE"]
$configs = $configs -replace "#REPORTPROGRESS#", $global:initcontent[$section]["REPORTPROGRESS"]
$configs = $configs -replace "#PREREQSTRICTMODE#", $global:initcontent[$section]["PREREQSTRICTMODE"]
$configs = $configs -replace "#LOGVERBOSITY#", $global:initcontent[$section]["LOGVERBOSITY"]
$configs = $configs -replace "#USERINPUTPOPUP#", $global:initcontent[$section]["USERINPUTPOPUP"]
$configs = $configs -replace "#UPGRADEPROJECT#", $global:initcontent[$section]["UPGRADEPROJECT"]


return $configs

}

Function Create-Var()
{
param (
    [Parameter(Mandatory=$true)]
    [string]$NTHDB
)

$VARHeader = @"
<?xml version="1.0" encoding="utf-8"?>
<variables xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="$($global:ConsoleScriptVariablesSchema)">
  <variable name="`$WorkingFolder$" value="#WORKINGFOLDER#" />
"@

$VARoraconn = @"
  <variable-group name="OracleConnection">
    <variable name="`$OracleHostName$" value="SRCDBHOST" />
    <variable name="`$OracleInstance$" value="SRCINSTNAME" />
    <variable name="`$OraclePort$" value="SRCPORT" />
    <variable name="`$OracleUserName$" value="SRCDBUSER" />
    <variable name="`$OraclePassword$" value="SRCDBPASS" />
    <variable name="`$OracleSchemaName$" value="SRCSCHEMA" />
  </variable-group>
"@

$VARsqlconn = @"
  <variable-group name="SQLconnection">
    <variable name="`$DBServerName$" value="TGTDBHOST" />
    <variable name="`$DatabaseName$" value="TGTDBNAME" />
    <variable name="`$DBUserID$" value="TGTDBUSER" />
    <variable name="`$DBPwd$" value="TGTDBPASS" />
  </variable-group>
"@


$VARReport = @"
  <variable-group name="Report">
    <variable name="`$SummaryReports$" value="`$WorkingFolder$" />
    <variable name="`$AssessmentReportFolderName$" value="#REPORTFOLDER#" />
    <variable name="`$AssessmentReports$" value="`$WorkingFolder$\`$AssessmentReportFolderName$" />
    <variable name="`$RefreshDBFolder$" value="`$WorkingFolder$" />
    <variable name="`$ConvertARReportsFolder$" value="`$WorkingFolder$\`$AssessmentReportFolderName$" />
    <variable name="`$SynchronizationReports$" value="`$WorkingFolder$" />
    <variable name="`$SaveScriptFolder$" value="`$WorkingFolder$\#SAVESCRIPT#" />
    <variable name="`$ConvertSQLReports$" value="`$WorkingFolder$\#CONVERTEDSQL#" />
    <variable name="`$SourceSQLFiles$" value="`$WorkingFolder$\#SOURCESQL#" />
  </variable-group>
"@

$VARProjectSpec = @"
  <variable-group name="ProjectSpecs">
    <variable name="`$project_name$" value="#PROJECTNAME#" />
    <variable name="`$project_overwrite$" value="#PROJECTOVERWRITE#" />
    <variable name="`$project_type$" value="#PROJECTTYPE#" />
    <variable name="`$project_folder$" value="`$WorkingFolder$\`$project_name$" />
  </variable-group>
"@




$FileVar = "$global:xmloutput\$global:VARSXML$NTHDB.xml"

out-file -FilePath $FileVar -Force -Encoding ascii

$workingdirectory=$global:initcontent["general"]["workingdirectory"]
Check-FileAndDir -Filedir "$workingdirectory" -CreateIt $true

if (! (Test-Path $workingdirectory))
{
   new-item -ItemType Directory -path $workingdirectory
}
$varheader = $varheader -replace "#WORKINGFOLDER#",$workingdirectory | out-file -Append -FilePath $FileVar -Encoding ascii


$result=$global:initcontent["sourcedb"][$nthdb]
$dbinfo=$result.split(",")


$VARoraconn = $VarOraconn -replace "SRCDBHOST",$dbinfo[0]
$Varoraconn = $varoraconn -replace "SRCPORT",$dbinfo[1]
$VARoraconn = $varoraconn -replace "SRCINSTNAME",$dbinfo[2]
$VARoraconn = $varoraconn -replace "SRCDBUSER",$dbinfo[3]
$VARoraconn = $varoraconn -replace "SRCDBPASS",$dbinfo[4]
$VARoraconn = $varoraconn -replace "SRCSCHEMA",$dbinfo[5]

$VARoraconn| Out-File -Append -FilePath $FileVar -Encoding ascii

$result=$global:initcontent["targetdb"][$nthdb]
$dbinfo=$result.split(",")

$VARsqlconn = $VARsqlconn -replace "TGTDBHOST",$dbinfo[0]
$VARsqlconn = $VARsqlconn -replace "TGTDBNAME",$dbinfo[2]
$VARsqlconn = $VARsqlconn -replace "TGTDBUSER",$dbinfo[3]
$VARsqlconn = $VARsqlconn -replace "TGTDBPASS",$dbinfo[4]
$global:tgtschema = $dbinfo[5]


$VarSQLConn | Out-File -Append -FilePath $FileVar -Encoding ascii


$assessreportfolder=Get-DBConfigParam -NTHDB "$NTHDB" -Key "reportfolder" -suffix "$NTHDB" 


if (! (Test-Path $workingdirectory\$assessreportfolder)) { new-item -ItemType Directory -path $workingdirectory\$assessreportfolder}

$convertedsql=Get-DBConfigParam -NTHDB "$NTHDB" -Key "convertedsql" -suffix "$NTHDB"
if (! (Test-Path $workingdirectory\$convertedsql)) { new-item -ItemType Directory -path $workingdirectory\$convertedsql}

$sourcesql=Get-DBConfigParam -NTHDB "$NTHDB" -Key "sourcesql" -suffix "$NTHDB"
if (! (Test-Path $workingdirectory\$sourcesql)) { new-item -ItemType Directory -path $workingdirectory\$sourcesql}

$savescript=Get-DBConfigParam -NTHDB "$NTHDB" -Key "savescript" -suffix "$NTHDB"
if (! (Test-Path $workingdirectory\$savescript)) { new-item -ItemType Directory -path $workingdirectory\$savescript}

$VarReport = $varReport -replace "#REPORTFOLDER#","$assessreportfolder"

$varReport = $VarReport -replace "#CONVERTEDSQL#", "$convertedsql"

$varReport = $VarReport -replace "#SOURCESQL#", "$sourcesql"

$VARReport = $VARReport -replace "#SAVESCRIPT#","$savescript"

$varreport | Out-File -Append -FilePath $FileVar -Encoding ascii


$projectname=Get-DBConfigParam -NTHDB "$NTHDB" -Key "projectname" -suffix "$NTHDB"
$projectoverwrite=Get-DBConfigParam -NTHDB "$NTHDB" -Key "projectoverwrite"
$projecttype=Get-DBConfigParam -NTHDB "$NTHDB" -Key "projecttype"



$VARProjectSpec = $VARProjectSpec -replace "#PROJECTNAME#",$projectname
$VARProjectSpec = $VARProjectSpec -replace "#PROJECTOVERWRITE#",$projectoverwrite
$VARProjectSpec = $VARProjectSpec -replace "#PROJECTTYPE#",$projecttype

$VARProjectSpec + "`n" + "</variables>" | Out-File -Append -FilePath $FileVar -Encoding ascii
}

Function Select-ObjectToCollect()
{
param (
    [Parameter(Mandatory=$true)]
    [String]$NTHDB
)


$allobjtocollect="<object-to-collect object-name=`"`$OracleSchemaName$`"/>"


$objtocollectlist=get-inicontent("$global:config")

      
        if ($objtocollectlist -ne $null)
        {
        
            if ($NTHDB -ne $null -and $objtocollectlist.Contains("$NTHDB") )
            {
                
                $objs=$objtocollectlist["$NTHDB"]["objtocollect"]
           
            }
            if ($objs -eq $null)
            {
                $objs=$objtocollectlist["alldb"]["objtocollect"]
            }

            if ($objs -eq $null)
            {
                return $allobjtocollect
            }
            $objects=$objs.split(",")
        
            $allobjtocollect=$allobjtocollect + "`n"

            for ($j=0;$j -lt $objectlist.count;$j++)
            {
                    $allobjtocollect=$allobjtocollect + "<object-to-collect object-name=`"`$OracleSchemaName$.$($objectlist[$j] -replace "\`$","`$`$`$`$`$`$`$")`" />`n"
            }
      
       } 

  return $allobjtocollect
}

Function Select-DataMigration()
{

param (
    [Parameter(Mandatory=$true)]
    [string]$Object,
    [String]$ObjectName,
    [String]$ObjectType,
    [Parameter(Mandatory=$true)]
    [String]$NTHDB
)

$TextInfo = (Get-Culture).TextInfo

switch -exact ($object)
{
   ('all' -or 'category')
   {
     $allobject=@"
    <migrate-data object-name="`$OracleSchemaName$.Tables"
                  object-type="category"
                  write-summary-report-to="`$SummaryReports$" report-errors="true" verbose="true" />
"@
    return $allobject
   } 
   'single'
   {

        $singleobject="<migrate-data write-summary-report-to=`"`$SummaryReports$\datamigreport.xml`" report-errors=`"true`" verbose=`"true`">`n"
        $global:objectlist=get-inicontent("$global:objconfig")
      
        if ($global:objectlist -ne $null)
        {
        
            if ($NTHDB -ne $null -and $global:objectlist.Contains("$NTHDB") )
            {
                
                $objs=$global:objectlist["$NTHDB"]["objecttype"]
           
            }
            if ($objs -eq $null)
            {
                $objs=$global:objectlist["alldb"]["objecttype"]
            }

            if ($objs -eq $null)
            {
                write-host "Either [$($NTHDB)] or [alldb] within file $($global:objconfig) doesnt contain list of objects..."
                exit 1
            }
        
            $objecttypes=$objs.split(",")
        

            for ($i=0;$i -lt $objecttypes.count;$i++)
            {
                if ($NTHDB -ne $null -and $global:objectlist.Contains("$NTHDB"))
                {
                    $lists=$global:objectlist["$NTHDB"][$objecttypes[$i]]
                }
                if ($lists -eq $null)
                {
                    $lists=$global:objectlist["alldb"][$objecttypes[$i]]
                }
          
               $objectlist=$lists.split(",")

               for ($j=0;$j -lt $objectlist.count;$j++)
               {
                    $singleobject=$singleobject + "<metabase-object object-name=`"`$OracleSchemaName$.$($objectlist[$j] -replace "\`$","`$`$`$`$`$`$`$")`" object-type=`"$($TextInfo.ToTitleCase($objecttypes[$i]))`" />`n"
               }
             }
       } 
       $singleobject=$singleobject+"</migrate-data >"
    return $singleobject

   }
}
  return $null
}

Function Select-SaveAsScript()
{
param (
    [Parameter(Mandatory=$true)]
    [string]$Object,
    [String]$ObjectName,
    [String]$ObjectType,
    [Parameter(Mandatory=$true)]
    [String]$NTHDB
)

$TextInfo = (Get-Culture).TextInfo

switch -exact ($object)
{
   'all'
   {
     $allobject=@"
   <save-as-script destination="`$SaveScriptFolder$\SourceDBScript.sql"
                    metabase="source"
                    object-name="`$OracleSchemaName$"
                    object-type="Schemas"
                    overwrite="true" />

    <save-as-script metabase="target" destination="`$SaveScriptFolder$\TargetDBScript.sql">
      <metabase-object object-name="[`$DatabaseName$]" object-type ="Databases" />
    </save-as-script>
"@
    return $allobject
   } 
   'single'
   {

     $singleobjectsrc="<save-as-script metabase=`"source`" destination=`"`$SaveScriptFolder$\SourceDBScript.sql`" overwrite=`"true`">`n"
     $singleobjecttgt="<save-as-script metabase=`"target`" destination=`"`$SaveScriptFolder$\TargetDBScript.sql`" overwrite=`"true`">`n"
      
      
      $global:objectlist=get-inicontent("$global:objconfig")
      
      if ($global:objectlist -ne $null)
      {
         if ($NTHDB -ne $null -and $global:objectlist.Contains("$NTHDB") )
        {
            $objs=$global:objectlist["$NTHDB"]["objecttype"]
        }
        if ($objs -eq $null)
        {
            $objs=$global:objectlist["alldb"]["objecttype"]
        }
        
        if ($objs -eq $null)
        {
            write-host "Either [$($NTHDB)] or [alldb] within file $($global:objconfig) doesnt contain list of objects..."
            exit 1
        }
        $objecttypes=$objs.split(",")
        

        for ($i=0;$i -lt $objecttypes.count;$i++)
        {
            if ($NTHDB -ne $null -and $global:objectlist.Contains("$NTHDB"))
            {
                $lists=$global:objectlist["$NTHDB"][$objecttypes[$i]]
            }
            if ($lists -eq $null)
            {
                $lists=$global:objectlist["alldb"][$objecttypes[$i]]
            }

            if ($lists -eq $null)
            {
                write-host "Either [$($NTHDB)] or [alldb] within file $($global:objconfig) doesnt contain list of objects..."
                exit 1
            }
          
           $objectlist=$lists.split(",")
           for ($j=0;$j -lt $objectlist.count;$j++)
           {
                $singleobjectsrc=$singleobjectsrc + "<metabase-object object-name=`"`$OracleSchemaName$.$($objectlist[$j] -replace "\`$","`$`$`$`$`$`$`$")`" object-type=`"$($TextInfo.ToTitleCase($objecttypes[$i]))`" />`n"
                $singleobjecttgt=$singleobjecttgt + "<metabase-object object-name=`"[`$DatabaseName$].$($global:tgtschema).$($objectlist[$j] -replace "\`$","`$`$`$`$`$`$`$")`" object-type=`"$($TextInfo.ToTitleCase($objecttypes[$i]))`" />`n"
           }
       }
      } 
       $singleobjectsrc=$singleobjectsrc+"</save-as-script>`n"
       $singleobjecttgt=$singleobjectsrc+"`n"+$singleobjecttgt+"</save-as-script>"
    return $singleobjecttgt
   }
   'category'
   {
    $categoryobjectsrc="<save-as-script destination=`"`$SaveScriptFolder$\SourceDBScript.sql`" metabase=`"source`" overwrite=`"true`">`n"

    $categoryobjecttgt="<save-as-script destination=`"`$SaveScriptFolder$\TargetDBScript.sql`" metabase=`"target`" overwrite=`"true`">`n"

    $objectcat=$objecttype.split(',')

      if ($objecttype -eq "")
      {
          $categoryobjecttgt=$categoryobjecttgt + "<metabase-object object-name=`"`$OracleSchemaName$.Tables`" object-type=`"category`"  />`n"
          $categoryobjectsrc=$categoryobjectsrc + "<metabase-object object-name=`"[`$DatabaseName$].$($global:tgtschema).Tables`" object-type=`"category`"  />`n"
      }
      else
      {

           for ($i=0;$i -lt $objectcat.count;$i++)
           {
               $categoryobjecttgt=$categoryobjecttgt + "<metabase-object object-name=`"`$OracleSchemaName$.$($TextInfo.ToTitleCase($objectcat[$i]))`" object-type=`"category`"  />`n"
               $categoryobjectsrc=$categoryobjectsrc + "<metabase-object object-name=`"[`$DatabaseName$].$($global:tgtschema).$($TextInfo.ToTitleCase($objectcat[$i]))`" object-type=`"category`"  />`n"
           }
      }

   $categoryobjecttgt=$categoryobjecttgt+"</save-as-script>"
   $categoryobjectsrc=$categoryobjectsrc+"</save-as-script>`n"
   return $categoryobjectsrc + $categoryobjecttgt

   }
}
  return $null
}   



Function Select-ConvertSchema()
{
param (
    [Parameter(Mandatory=$true)]
    [string]$Object,
    [String]$ObjectName,
    [String]$ObjectType,
    [Parameter(Mandatory=$true)]
    [String]$NTHDB
)

$TextInfo = (Get-Culture).TextInfo

switch -exact ($object)
{
   'all'
   {
     $allobject=@"
    <convert-schema object-name="`$OracleSchemaName$"
                                object-type="Schemas"
                                write-summary-report-to="`$SummaryReports$"
                                verbose="true"
                                report-errors="true"
                                conversion-report-folder="`$ConvertARReportsFolder$"
                                conversion-report-overwrite="true" />
"@
    return $allobject
   } 
   'single'
   {

     $singleobject=@"
     <convert-schema write-summary-report-to="`$SummaryReports$"
                                verbose="true"
                                report-errors="true"
                                conversion-report-folder="`$ConvertARReportsFolder$"
                                conversion-report-overwrite="true">`n
"@
      
      
      $global:objectlist=get-inicontent("$global:objconfig")
      
      if ($global:objectlist -ne $null)
      {
         if ($NTHDB -ne $null -and $global:objectlist.Contains("$NTHDB") )
        {
            $objs=$global:objectlist["$NTHDB"]["objecttype"]
        }
        if ($objs -eq $null)
        {
            $objs=$global:objectlist["alldb"]["objecttype"]
        }
        
        if ($objs -eq $null)
        {
            write-host "Either [$($NTHDB)] or [alldb] within file $($global:objconfig) doesnt contain list of objects..."
            exit 1
        }
        $objecttypes=$objs.split(",")
        

        for ($i=0;$i -lt $objecttypes.count;$i++)
        {
            if ($NTHDB -ne $null -and $global:objectlist.Contains("$NTHDB"))
            {
                $lists=$global:objectlist["$NTHDB"][$objecttypes[$i]]
            }
            if ($lists -eq $null)
            {
                $lists=$global:objectlist["alldb"][$objecttypes[$i]]
            }

            if ($lists -eq $null)
            {
                write-host "Either [$($NTHDB)] or [alldb] within file $($global:objconfig) doesnt contain list of objects..."
                exit 1
            }
           
           $objectlist=$lists.split(",")
           for ($j=0;$j -lt $objectlist.count;$j++)
           {
                $singleobject=$singleobject + "<metabase-object object-name=`"`$OracleSchemaName$.$($objectlist[$j] -replace "\`$","`$`$`$`$`$`$`$")`" object-type=`"$($TextInfo.ToTitleCase($objecttypes[$i]))`" />`n"
           }
         }
       } 
       $singleobject=$singleobject+"</convert-schema>"
    return $singleobject
   }
   'category'
   {
    $categoryobject=@"
    <convert-schema 
    write-summary-report-to="`$SummaryReports$"
                                verbose="true"
                                report-errors="true"
                                conversion-report-folder="`$ConvertARReportsFolder$"
                                conversion-report-overwrite="true">`n
"@

    $objectcat=$objecttype.split(',')

    if ($objecttype -eq "")
    {
        $categoryobject=$categoryobject + "<metabase-object object-name=`"`$OracleSchemaName$.Tables`" object-type=`"category`"  />`n"
    }
    else
    {
   
       for ($i=0;$i -lt $objectcat.count;$i++)
       {
           $categoryobject=$categoryobject + "<metabase-object object-name=`"`$OracleSchemaName$.$($TextInfo.ToTitleCase($objectcat[$i]))`" object-type=`"category`"  />`n"
       }

    }
   return $categoryobject + "`n</convert-schema>"
   }
}
  return $null
}   


Function Select-SyncTarget()
{
param (
    [Parameter(Mandatory=$true)]
    [string]$Object,
    [String]$ObjectName,
    [String]$ObjectType,
    [Parameter(Mandatory=$true)]
    [String]$NTHDB
)

$TextInfo = (Get-Culture).TextInfo

if ($global:initcontent.containskey("$NTHDB"))
{
    $synctargetonerror=$global:initcontent["$NTHDB"]["synctargetonerror"]
}

if ($synctargetonerror -eq $null)
{
    $synctargetonerror=$global:initcontent["alldb"]["synctargetonerror"]
}

switch -exact ($object)
{
   'all'
   {
     $allobject=@"
    <synchronize-target object-name="[`$DatabaseName$].$($global:tgtschema)"
                                object-type="Schemas"
                                on-error="fail-script"
                                report-errors-to="`$SynchronizationReports$" />`n
"@
    return $allobject
   } 
   'single'
   {

     $singleobject="<synchronize-target on-error=`"$synctargetonerror`" report-errors-to=`"`$SynchronizationReports$`">`n"
      
      
      $global:objectlist=get-inicontent("$global:objconfig")
      
      if ($global:objectlist -ne $null)
      {
         if ($NTHDB -ne $null -and $global:objectlist.Contains("$NTHDB") )
        {
            $objs=$global:objectlist["$NTHDB"]["objecttype"]
        }
        if ($objs -eq $null)
        {
            $objs=$global:objectlist["alldb"]["objecttype"]
        }
        
        if ($objs -eq $null)
        {
            write-host "Either [$($NTHDB)] or [alldb] within file $($global:objconfig) doesnt contain list of objects..."
            exit 1
        }
        $objecttypes=$objs.split(",")
        

        for ($i=0;$i -lt $objecttypes.count;$i++)
        {
            if ($NTHDB -ne $null -and $global:objectlist.Contains("$NTHDB"))
            {
                $lists=$global:objectlist["$NTHDB"][$objecttypes[$i]]
            }
            if ($lists -eq $null)
            {
                $lists=$global:objectlist["alldb"][$objecttypes[$i]]
            }

            if ($lists -eq $null)
            {
                write-host "Either [$($NTHDB)] or [alldb] within file $($global:objconfig) doesnt contain list of objects..."
                exit 1
            }
          
           $objectlist=$lists.split(",")
           for ($j=0;$j -lt $objectlist.count;$j++)
           {
                $singleobject=$singleobject + "<metabase-object object-name=`"[`$DatabaseName$].$($global:tgtschema).$($objectlist[$j] -replace "\`$","`$`$`$`$`$`$`$")`" object-type=`"$($TextInfo.ToTitleCase($objecttypes[$i]))`" />`n"
           }
         }
       } 
       $singleobject=$singleobject+"</synchronize-target>"
    return $singleobject
   }
   'category'
   {
    $categoryobject="<synchronize-target report-errors-to=`"`$SynchronizationReports$`" on-error=`"$synctargetonerror`">`n"
    $objectcat=$objecttype.split(',')

    if ($objecttype -eq "")
    {
       $categoryobject=$categoryobject + "<metabase-object object-name=`"[`$DatabaseName$].$($global:tgtschema).Tables`" object-type=`"category`"  />`n"
    }
    else
    {
       for ($i=0;$i -lt $objectcat.count;$i++)
       {
           $categoryobject=$categoryobject + "<metabase-object object-name=`"[`$DatabaseName$].$($global:tgtschema).$($TextInfo.ToTitleCase($objectcat[$i]))`" object-type=`"category`"  />`n"
       }
    }
   
   return $categoryobject + "`n</synchronize-target>"
   }
}
  return $null
}   

Function Select-RefreshDatabase()
{
param (
    [Parameter(Mandatory=$true)]
    [string]$Object,
    [String]$ObjectName,
    [String]$ObjectType,
    [Parameter(Mandatory=$true)]
    [String]$NTHDB
)

$TextInfo = (Get-Culture).TextInfo
if ($global:initcontent.containskey("$NTHDB"))
{
    $refreshdbonerror=$global:initcontent["$NTHDB"]["refreshdbonerror"]
}
if ($refreshdbonerror -eq $null)
{
    $refreshdbonerror=$global:initcontent["alldb"]["refreshdbonerror"]
}

switch -exact ($object)
{
   'all'
   {
     $allobject=@"
    <refresh-from-database object-name="`$OracleSchemaName$"
                                object-type="Schemas"
                                on-error="$refreshdbonerror"
                                report-errors-to="`$RefreshDBFolder$" />`n
"@
    return $allobject
   } 
   'single'
   {

     $singleobject="<refresh-from-database on-error=`"$refreshdbonerror`" report-errors-to=`"`$RefreshDBFolder$`">`n"
      
      
      $global:objectlist=get-inicontent("$global:objconfig")
      
      if ($global:objectlist -ne $null)
      {
        if ($NTHDB -ne $null -and $global:objectlist.Contains("$NTHDB") )
        {
            $objs=$global:objectlist["$NTHDB"]["objecttype"]
        }
        if ($objs -eq $null)
        {
            $objs=$global:objectlist["alldb"]["objecttype"]
        }
        
        if ($objs -eq $null)
        {
            write-host "Either [$($NTHDB)] or [alldb] within file $($global:objconfig) doesnt contain list of objects..."
            exit 1
        }
        $objecttypes=$objs.split(",")
        

        for ($i=0;$i -lt $objecttypes.count;$i++)
        {
            if ($NTHDB -ne $null -and $global:objectlist.Contains("$NTHDB"))
            {
                $lists=$global:objectlist["$NTHDB"][$objecttypes[$i]]
            }
            if ($lists -eq $null)
            {
                $lists=$global:objectlist["alldb"][$objecttypes[$i]]
            }
          
            if ($lists -eq $null)
            {
                write-host "Either [$($NTHDB)] or [alldb] within file $($global:objconfig) doesnt contain list of objects..."
                exit 1
            }
           $objectlist=$lists.split(",")
           for ($j=0;$j -lt $objectlist.count;$j++)
           {
                $singleobject=$singleobject + "<metabase-object object-name=`"`$OracleSchemaName$.$($objectlist[$j] -replace "\`$","`$`$`$`$`$`$`$")`" object-type=`"$($TextInfo.ToTitleCase($objecttypes[$i]))`" />`n"
           }
         }
       } 
       $singleobject=$singleobject+"</refresh-from-database>"
    return $singleobject
   }

   'category'
   {
    $categoryobject="<refresh-from-database report-errors-to=`"`$RefreshDBFolder$`" on-error=`"$refreshdbonerror`">`n"
    
    $objectcat=$objecttype.split(',')

    if ($objecttype -eq "")
    {
       $categoryobject=$categoryobject + "<metabase-object object-name=`"`$OracleSchemaName$.Tables`" object-type=`"category`"  />`n"
    }
    else
    {
   
       for ($i=0;$i -lt $objectcat.count;$i++)
       {
           $categoryobject=$categoryobject + "<metabase-object object-name=`"`$OracleSchemaName$.$($TextInfo.ToTitleCase($objectcat[$i]))`" object-type=`"category`"  />`n"
       }
    }
   
   return $categoryobject + "`n</refresh-from-database>"
   }
}
  return $null
}   

Function Select-AssessmentObject()
{

param (
    [Parameter(Mandatory=$true)]
    [string]$Object,
    [String]$ObjectName,
    [String]$ObjectType,
    [Parameter(Mandatory=$true)]
    [String]$NTHDB
)

$TextInfo = (Get-Culture).TextInfo

switch -exact ($object)
{
   'all'
   {
     $allobject=@"
    <generate-assessment-report object-name="`$OracleSchemaName$"
                                object-type="Schemas"
                                write-summary-report-to="`$SummaryReports$"
                                verbose="true"
                                report-errors="true"
                                assessment-report-folder="`$AssessmentReports$"
                                assessment-report-overwrite="true" />

"@
    return $allobject
   } 
   'single'
   {

     $singleobject=@"
     <generate-assessment-report write-summary-report-to="`$SummaryReports$"
                                verbose="true"
                                report-errors="true"
                                assessment-report-folder="`$AssessmentReports$"
                                assessment-report-overwrite="true">`n
"@
     
     Check-FileAndDir "$global:objconfig"

     $global:objectlist=get-inicontent("$global:objconfig")
     

     if ($global:objectlist -ne $null)
     {
        if ($NTHDB -ne $null -and $global:objectlist.Contains("$NTHDB") )
        {
            $objs=$global:objectlist["$NTHDB"]["objecttype"]
        }
        if ($objs -eq $null)
        {
            $objs=$global:objectlist["alldb"]["objecttype"]
        }
        if ($objs -eq $null)
        {
            write-host "Either [$($NTHDB)] or [alldb] within file $($global:objconfig) doesnt contain list of objects..."
            exit 1
        }


        $objecttypes=$objs.split(",")
        

        for ($i=0;$i -lt $objecttypes.count;$i++)
        {
            if ($NTHDB -ne $null -and $global:objectlist.Contains("$NTHDB"))
            {
                $lists=$global:objectlist["$NTHDB"][$objecttypes[$i]]
            }
            else
            {
                $lists=$global:objectlist["alldb"][$objecttypes[$i]]
            }
            
            if ($lists -eq $null)
            {
               continue
            }
            $objectlist=$lists.split(",")
            for ($j=0;$j -lt $objectlist.count;$j++)
            {
                $singleobject=$singleobject + "<metabase-object object-name=`"`$OracleSchemaName$.$($objectlist[$j] -replace "\`$","`$`$`$`$`$`$`$")`" object-type=`"$($TextInfo.ToTitleCase($objecttypes[$i]))`" />`n"
            }
        }
     } 
     $singleobject=$singleobject+"</generate-assessment-report>"
     return $singleobject
   }
   'category'
   {
      $categoryobject="<generate-assessment-report write-summary-report-to=`"`$SummaryReports$`" report-errors=`"true`">`n"

      $objectcat=$objecttype.split(',')
      if ($objecttype -eq "")
      {
         $categoryobject = $categoryobject + "<metabase-object object-name=`"`$OracleSchemaName$.Tables`" object-type=`"category`"  />`n"
      }
      else
      {
     
        for ($i=0;$i -lt $objectcat.count;$i++)
        {
              $categoryobject=$categoryobject + "<metabase-object object-name=`"`$OracleSchemaName$.$($TextInfo.ToTitleCase($objectcat[$i]))`" object-type=`"category`"  />`n"
        }

      }
      return $categoryobject + "`n</generate-assessment-report>"
   }
}
  return $null
}

Function Create-AssessmentReport()
{
param (
    [Parameter(Mandatory=$true)]
    [string]$NTHDB
)

$assessmentreport = @"
 <script-commands>
    <create-new-project project-folder="`$project_folder$"
                        project-name="`$project_name$"
                        project-type="`$project_type$"
                        overwrite-if-exists="`$project_overwrite$" />
    <connect-source-database server="$OracleConnection">
     OBJECTTOCOLLECT
    </connect-source-database>
     OBJECTSELECTIONS 
    <!-- Save project -->
    <save-project />
    <!-- Close project -->
    <close-project />
  </script-commands>
</ssma-script-file>
"@  




   if ($global:initcontent.containskey("$NTHDB"))
   {
      $object=$global:initcontent["$NTHDB"]["object"]
      if ($object -eq $null) {  $object=$global:initcontent["alldb"]["object"] }
      $objecttype=$global:initcontent["$NTHDB"]["objecttype"]
      if ($objecttype -eq $null) { $objecttype=$global:initcontent["alldb"]["objecttype"] }
      $assessmentreport = $assessmentreport -replace "OBJECTTOCOLLECT",(Select-ObjectToCollect -NTHDB "$NTHDB")
   }
   else
   {
      $object=$global:initcontent["alldb"]["object"]
      $objecttype=$global:initcontent["alldb"]["objecttype"]
      $assessmentreport = $assessmentreport -replace "OBJECTTOCOLLECT",(Select-ObjectToCollect -NTHDB "db1")
   }



   
   if ($object -eq "all" -or $object -eq 'single')
   {
       $assessmentreport = $assessmentreport -replace "OBJECTSELECTIONS",(Select-AssessmentObject -Object $object -NTHDB $NTHDB)
   }
   else
   {

       $assessmentreport = $assessmentreport -replace "OBJECTSELECTIONS",(Select-AssessmentObject -Object "category" -ObjectType $objecttype -NTHDB $NTHDB)

   }



   $FileAssess = "$global:xmloutput\$global:ASSESSXML$NTHDB.xml"
   $assessmentreport = "<?xml version=`"1.0`" encoding=`"utf-8`"?>
<ssma-script-file xmlns:xsi=`"http://www.w3.org/2001/XMLSchema-instance`" xsi:noNamespaceSchemaLocation=`"$($global:O2SSConsoleScriptSchema)`">
   $(create-config -section "assessment")
   $assessmentreport
   " | out-file -FilePath $FileAssess -Encoding ascii -force
}


Function Check-Database()
{
param (
    [Parameter(Mandatory=$true)]
    [string]$NTHDB
)





$FileObjs = "$global:xmloutput\$global:storeobjects$NTHDB.lst" 


$result=$global:initcontent["sourcedb"]["$NTHDB"]
$dbinfo=$result.split(",")



$SRCDBHOST=$dbinfo[0]
$SRCPORT=$dbinfo[1]
$SRCINSTNAME=$dbinfo[2]
$SRCDBUSER=($dbinfo[3]).toUpper()
$SRCPASS=$dbinfo[4]
$SRCSCHEMA=$dbinfo[5].toUpper()

$datasource = "//$($SRCDBHOST):$($SRCPORT)/$($SRCINSTNAME)"
$connectionString = 'User Id=' + $SRCDBUSER + ';Password=' + $SRCPASS + ';Data Source=' + $datasource
$connection = New-Object Oracle.ManagedDataAccess.Client.OracleConnection($connectionString)
$connection.open()
$command=$connection.CreateCommand()

$query=""

if ($global:objectlist -ne $null)
{
  out-file -FilePath $FileObjs -Encoding ascii -force
  
  if ($NTHDB -ne $null -and $global:objectlist.Contains("$NTHDB") )
  {
      $objs=$global:objectlist["$NTHDB"]["objecttype"]
  }
  else
  {
      $objs=$global:objectlist["alldb"]["objecttype"]
  }
 
  $objecttypes=$objs.split(",")     
  for ($i=0;$i -lt $objecttypes.count;$i++)
  {
   
      if ($NTHDB -ne $null -and $global:objectlist.Contains("$NTHDB"))
      {
          $lists=$global:objectlist["$NTHDB"][$objecttypes[$i]]
      }
      else
      {
          $lists=$global:objectlist["alldb"][$objecttypes[$i]]
      }
      if ($lists -eq $null)
      {
          continue
      }
      $objectlist=$lists.split(",")

      $query="select object_name,object_type from dba_objects where owner='"+$SRCSCHEMA+"' and object_type='"+$($objecttypes[$i] -replace ".$").toUpper() +"' order by 1"

      $command.CommandText=$query
      $reader=$command.ExecuteReader()
      while ($reader.Read()) {
             Write-Output "$($SRCSCHEMA).$($reader.GetString(0).padright(40," ")) $($reader.GetString(1)) $($objectlist.toUpper().Contains($($reader.GetString(0))))" | out-file -FilePath $FileObjs -Encoding ascii -Append
      }

   }
} 

$connection.Close()
}


Function Query-Database()
{
param (
    [Parameter(Mandatory=$true)]
    [string]$NTHDB,
    [Parameter(Mandatory=$true)]
    [String]$SQLQuery,
    [String]$SpoolFile
)




$FileObjs = "$global:xmloutput\$global:storeobjects" 

$result=$global:initcontent["sourcedb"]["$NTHDB"]


$dbinfo=$result.split(",")

$SRCDBHOST=$dbinfo[0]
$SRCPORT=$dbinfo[1]
$SRCINSTNAME=$dbinfo[2]
$SRCDBUSER=($dbinfo[3]).toUpper()
$SRCPASS=$dbinfo[4]
$SRCSCHEMA=$dbinfo[5].toUpper()

$datasource = "//$($SRCDBHOST):$($SRCPORT)/$($SRCINSTNAME)"
$connectionString = 'User Id=' + $SRCDBUSER + ';Password=' + $SRCPASS + ';Data Source=' + $datasource
$connection = New-Object Oracle.ManagedDataAccess.Client.OracleConnection($connectionString)

if (Test-Path $SQLQuery)
{
   write-host "Reading from a SQL file $SQLQuery"
   $SQLTemp=Get-content -Path "$SQLQuery" -Encoding ascii

}
else
{
   $SQLTemp="$SQLQuery"
}
try {
        $connection.open()
        $command=$connection.CreateCommand()
        $SQLBeginEnd=""
        $SQLSelect=""
        foreach ($SQLQUery in $SQLTemp)
        {
            if ( $SQLQUery -eq "" ) { continue }
            
            if ( $SQLQuery.toUpper().contains('BEGIN') -or $SQLBeginEnd -ne "")
            {

                $SQLBeginEnd="$SQLBeginEnd`n$SQLQuery" 
                
                if ( $SQLQuery.contains('END;') )
                {
         
                   $command.CommandText="$SQLBeginEnd"
                   $reader=$command.ExecuteReader()
                   $SQLBeginEnd=""
                }   
                
            }
            elseif ( $SQLQuery.ToUpper().contains('SELECT') -or $SQLSelect -ne "")
            {
                
                $SQLSelect="$SQLSelect`n$SQLQuery"
                if ( $SQLQuery.contains(';') )
                {
                   $command.CommandText="$($SQLSelect -replace ".$")"
                   $reader=$command.ExecuteReader()
                   $SQLSelect=""
                }   
            }
            else
            { $SQLSelect=""
              $SQLBeginEnd=""
              continue }
        }

        $schemaTable = $reader.GetSchemaTable();
        $colname=""
        for ($i=0;$i -lt $reader.fieldcount;$i++)
        {
            $DataRow  = $schemaTable.Rows[$i]
            if ($reader.FieldCount -gt 5)
            {
               $colname="$colname,$($datarow["COLUMNNAME"])"
            }
            else
            {
               $colname="$colname $($datarow["COLUMNNAME"])"
            }
                    
        }
        Write-Output "`n`n====================================================="
        write-output "Server Name   : $SRCDBHOST"
        Write-Output "Instance Name : $SRCINSTNAME"
        Write-Output "Schema Name   : $SRCSCHEMA"
        Write-Output "$($colname.trimstart(",").trimstart(" "))"

        if ($Spoolfile -eq "" -or $SpoolFile -eq $null)
        { 
          
            while ($reader.Read()) {
                $displayrow=""
                for ($i=0;$i -lt $reader.fieldcount;$i++) { $displayrow="$displayrow,$($reader.GetValue($i))" }
                Write-Output "$($displayrow.trimstart(",").trimstart(" "))"
            }
        }
        else
        {
            $flag=0
            while ($reader.Read()) {
                $displayrow=""
                for ($i=0;$i -lt $reader.fieldcount;$i++) { $displayrow="$displayrow,$($reader.GetValue($i))" }
                if ($flag -eq 0 )
                {
                    Write-Output "$($displayrow.trimstart(",").trimstart(" "))" | out-file -FilePath $SpoolFile -force
                    $flag=1
                }
                else
                {
                    Write-Output "$($displayrow.trimstart(",").trimstart(" "))" | out-file -FilePath $SpoolFile -Append
                }
            }
         }
    }
catch {
         write-host $_
    }
finally 
     {
    $connection.Close()
    }
}

Function Get-Filecontent()
{
param (
    [Parameter(Mandatory=$true)]
    [string]$Filename
)

   $output=@()
   if (Test-path -LiteralPath $Filename)
   {
      $output=get-content -LiteralPath $Filename
      return $output
   }
   else
   {
      return $Null
   }
}

Function Query-DB-toCSV()
{
param (
    [Parameter(Mandatory=$true)]
    [string]$NTHDB,
    [Parameter(Mandatory=$true)]
    [string]$Filename

)



$FileObjs = "$global:xmloutput\$global:csvfile" 

$result=$global:initcontent["sourcedb"]["$NTHDB"]


$dbinfo=$result.split(",")

$SRCDBHOST=$dbinfo[0]
$SRCPORT=$dbinfo[1]
$SRCINSTNAME=$dbinfo[2]
$SRCDBUSER=($dbinfo[3]).toUpper()
$SRCPASS=$dbinfo[4]
$SRCSCHEMA=$dbinfo[5].toUpper()

$datasource = "//$($SRCDBHOST):$($SRCPORT)/$($SRCINSTNAME)"
$connectionString = 'User Id=' + $SRCDBUSER + ';Password=' + $SRCPASS + ';Data Source=' + $datasource
$connection = New-Object Oracle.ManagedDataAccess.Client.OracleConnection($connectionString)


try {
        $connection.open()
        $command=$connection.CreateCommand()
        
        $filecontents=Get-Filecontent -Filename $Filename
        $command.BindByName=$true
        $oraparam= $command.CreateParameter()
        $oraparam.ParameterName="OBJNAME"
        $oraParam.Value = ""
        $command.Parameters.Add($oraParam) | Out-Null
        [System.Collections.ArrayList]$arrayvar = @()
        for ($j=0;$j -lt $filecontents.count;$j++)
        {
           
           $oraParam.Value = $filecontents[$j]
      
           $SQLquery="select owner,object_type,object_name from dba_objects where object_name=:OBJNAME"
           $command.CommandText=$SQLquery
           $reader=$command.ExecuteReader()
           $displayrow=""
           $owner=""
           $objtype=""
           
           while ($reader.Read()) 
           {
               $null=$arrayvar.add("$($reader.getvalue(0)),$($reader.getvalue(1)),$($reader.getvalue(2))")
           } 
        }
           $arrayvar.Sort()
          

           for ($i=0;$i -ne $arrayvar.count;$i++)
           {
                $thecols=$arrayvar[$i].ToString().split(",")
              
                if ($owner -ne $thecols[0])
                {
                   $owner=$thecols[0]
                   if ($objtype -ne $thecols[1])
                   {
                      $objtype=$thecols[1]
                      $listofobjects
                      $listofobjects="`n$owner.$objtype=$($thecols[2])"
                   }
                   else
                   {
                      $listofobjects="$listofobjects,$($thecols[2])"
                   }
                }
                else
                {
                   if ($objtype -ne $thecols[1])
                   {
                      $objtype=$thecols[1]
                      $listofobjects
                      $listofobjects="`n$owner.$objtype=$($thecols[2])"
                   }
                   else
                   {
                      $listofobjects="$listofobjects,$($thecols[2])"
                   }
                }


               
           }

    }
catch {
         write-host $_
    }
finally 
     {
    $connection.Close()
    }
}

#Main

$maxdbs=$global:initcontent["general"]["maxdbs"]
$threads=$global:initcontent["general"]["threads"]


Check-FileAndDir "$global:SSMAconsole"
Check-FileAndDir "$global:O2SSConsoleScriptSchema"
Check-FileAndDir "$global:O2SSConsoleScriptServersSchema"
Check-FileAndDir "$global:ConsoleScriptVariablesSchema"
Check-FileAndDir "$global:instantclientdir"
Add-Type -Path "$($global:instantclientdir)\odp.net\managed\common\Oracle.ManagedDataAccess.dll"
Check-FileAndDir($global:OMDA)

$global:RunspacePool = [runspacefactory]::CreateRunspacePool(1, $threads)
$global:RunspacePool.Open()
$global:Jobs = @()



$global:xmloutput=$global:initcontent["general"]["xmloutput"]
Check-FileAndDir -filedir $global:xmloutput -CreateIt $true

for ($db=1;$db -le $maxdbs;$db++)
{
    $PowerShell = [powershell]::Create()
    $PowerShell.RunspacePool = $global:RunspacePool

    if (! ($global:initcontent.sourcedb.contains("db$($db)")))
    {
       write-host "Database db$($db) config is disabled or config section from [db$($db)] to [db$($maxdbs)] are not defined!!.."
       write-host "You have set Max DB to be $($maxdbs), please check the config file!!"
       exit
    }

    if ($global:initcontent.containskey("db$($db)"))
    {
      if ($global:initcontent["db$($db)"]["enabled"] -eq "false") { continue }
      if ($global:initcontent["db$($db)"]["datamigration"] -eq $false) {$datamigration=$false} else {$datamigration=$true}
      if ($global:initcontent["db$($db)"]["savescript"] -eq $false) {$savescript=$false} else {$savescript=$true}
      if ($global:initcontent["db$($db)"]["refreshdatabase"] -eq $false) {$refreshdatabase=$false} else {$refreshdatabase=$true}
      if ($global:initcontent["db$($db)"]["synctarget"] -eq $false) {$synctarget=$false} else {$synctarget=$true}
      if ($global:initcontent["db$($db)"]["convertschema"] -eq $false) {$convertschema=$false} else {$convertschema=$true}
    }
    else
    {
      write-host "Sourcedb db$($db) is defined but the config [db$($db)] does not exist on the config file.."
      exit 1
    }


    $global:targetplatform=Get-DBConfigParam -NTHDB "db$($db)" -Key "targetplatform"
    Create-Conn "$global:targetplatform" -NTHDB "db$($db)"
    Create-var -NTHDB "db$($db)"

    if (! [string]::IsNullOrWhiteSpace($SQLQuery) -and $Mode -eq "querydb" )
    {
        write-output "Querying database db$($db) ..."
        Query-Database -SQLQuery $SQLQuery -NTHDB "db$($db)" -SpoolFile $SpoolFile
       
    }
    elseif ($Mode -eq "lookupdb")
    {

        write-output "Checking database db$($db) ..."
        $global:objectlist=get-inicontent("$global:objconfig")

        Check-Database -NTHDB "db$($db)"
    }
    elseif ($Mode -eq "listobjects")
    {
        Query-DB-toCSV -NTHDB "db$($db)" -Filename "$ListObjFilename"
    }
    elseif ($Mode -eq "convertsql")
    {

        Create-SQL-Conversion -ConvertMode $ConvertMode -SQlQuery $SQLQuery
        $PowerShell.AddScript("start-process -FilePath `"$($global:SSMAconsole) -ArgumentList `"-s $($global:scriptdir)\$($global:ConvertSQLXML).xml -c $($global:scriptdir)\$($global:ConnXML)db$($db).xml  -v $($global:scriptdir)\$($global:VARSXML)db$($db).xml`" -RedirectStandardError `"$($global:scriptdir)\convertsqlerrdb$($db).log`" -RedirectStandardOutput `"$($global:scriptdir)\convertsqloutdb$($db).log`" -wait")


    }
    elseif ($Mode -eq "assess" -or $Mode -eq "convert" -or $Mode -eq "all")
    {

        write-output "Creating assessment Report for database db$($db) ..."
        Create-AssessmentReport "db$($db)"

        write-output "Performing conversion on database db$($db) ..."
        Create-Conversion "db$($db)" -RefreshDatabase $refreshdatabase -SyncTarget $synctarget -ConvertSchema $Convertschema -SaveScript $savescript -DataMigration $datamigration

        
    
        if ($Mode -eq "assess" -or $Mode -eq "all")
        {

            write-output "Asessing database db$($db) ..."
            if (test-path -path "$global:scriptdir\assessmentoutdb$($db).log") { remove-item -path "$global:scriptdir\assessmentoutdb$($db).log" -force }
            if (test-path -path "$global:scriptdir\assessmenterrdb$($db).log") { remove-item -path "$global:scriptdir\assessmenterrdb$($db).log" -force }

            #start-process -FilePath $global:SSMAconsole -ArgumentList "-s $global:xmloutput\$($global:AssessXML)db$($db).xml -c $global:xmloutput\$($global:ConnXML)db$($db).xml -v $global:xmloutput\$($global:VARSXML)db$($db).xml" -RedirectStandardError "$global:scriptdir\assessmenterrdb$($db).log" -RedirectStandardOutput "$global:scriptdir\assessmentoutdb$($db).log" -wait -ErrorAction stop
            $PowerShell.AddScript("start-process -FilePath `"$($global:SSMAconsole)`" -ArgumentList `"-s $($global:xmloutput)\$($global:AssessXML)db$($db).xml -c $($global:xmloutput)\$($global:ConnXML)db$($db).xml -v $($global:xmloutput)\$($global:VARSXML)db$($db).xml`" -RedirectStandardError `"$($global:scriptdir)\assessmenterrdb$($db).log`" -RedirectStandardOutput `"$($global:scriptdir)\assessmentoutdb$($db).log`" -wait -ErrorAction stop")
        }

        if ($Mode -eq "convert" -or $Mode -eq "all")
        {

            write-output "Converting database db$($db) ..."
            if (test-path -path "$global:scriptdir\convertoutdb$($db).log") { remove-item -path "$global:scriptdir\convertoutdb$($db).log" -force }
            if (test-path -path "$global:scriptdir\converterrdb$($db).log") { remove-item -path "$global:scriptdir\converterrdb$($db).log" -force }

            #start-process -FilePath $global:SSMAconsole -ArgumentList "-s $global:xmloutput\$($global:ConversionXML)db$($db).xml -c $global:xmloutput\$($global:ConnXML)db$($db).xml -v $global:xmloutput\$($global:VARSXML)db$($db).xml" -RedirectStandardError "$global:scriptdir\converterrdb$($db).log" -RedirectStandardOutput "$global:scriptdir\convertoutdb$($db).log" -wait -ErrorAction stop
            $PowerShell.AddScript("start-process -FilePath `"$($global:SSMAconsole)`" -ArgumentList `"-s $($global:xmloutput)\$($global:ConversionXML)db$($db).xml -c $($global:xmloutput)\$($global:ConnXML)db$($db).xml -v $($global:xmloutput)\$($global:VARSXML)db$($db).xml`" -RedirectStandardError `"$($global:scriptdir)\converterrdb$($db).log`" -RedirectStandardOutput `"$($global:scriptdir)\convertoutdb$($db).log`" -wait -ErrorAction stop")
        }
    }
    else
    {
        write-host "Wrong Mode!!"
    }

        
    $global:Jobs += $PowerShell.BeginInvoke()

}

while ($global:Jobs.IsCompleted -contains $false) {Start-Sleep -Milliseconds 100}



