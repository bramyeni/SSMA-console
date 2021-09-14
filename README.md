# Run SSMA Console
<pre>
Get-Help .\RunSSMA.ps1 -full

NAME
    C:\mypowershell\RunSSMA.ps1

SYNOPSIS
    Run SSMA console with configurable parameters through command line
    it can perform automated assessments and conversions for multiple databases


SYNTAX
    C:\mypowershell\RunSSMA.ps1 [[-Mode] <String>] [[-OracleConnection] <String>] [[-SQLQuery] <String>]
    [[-ListObjFilename] <String>] [[-ConvertMode] <String>] [[-SpoolFile] <String>] [<CommonParameters>]


DESCRIPTION
    Run SSMA console with configurable parameters


PARAMETERS
    -Mode <String>
        Choose SSMA mode
        all         = Perform SSMA Assessment and conversion
        assess      = Perform SSMA Assessment only (default)
        convert     = Perform SSMA Conversion only
        gensql      = Generate sql script from source database only
        querydb     = Query source database
        lookupdb    = Query source database and check whether the objects within objectlist.ini matches
        listobjects = Generate group of objecs from a file pointed by Parameter ListObjFilename (default=objects.txt)
        convertsql  = Perform SSMA save as script which also rely on parameter ConvertMode and SQLQuery

        Required?                    false
        Position?                    1
        Default value                assess
        Accept pipeline input?       false
        Accept wildcard characters?  false

    -OracleConnection <String>
        Source oracle connection name by default source_oraservice

        Required?                    false
        Position?                    2
        Default value                source_oraservice
        Accept pipeline input?       false
        Accept wildcard characters?  false

    -SQLQuery <String>
        This parameter can be a query or a file contains list of queries

        Required?                    false
        Position?                    3
        Default value
        Accept pipeline input?       false
        Accept wildcard characters?  false

    -ListObjFilename <String>
        see Parameter Mode

        Required?                    false
        Position?                    4
        Default value                objects.txt
        Accept pipeline input?       false
        Accept wildcard characters?  false

    -ConvertMode <String>
        apply only when Parameter convertsql is selected
        list of ConvertMode are:
        sqlcmdtofile      = Convert Query on SQLquery will be spooled to an output file
        sqlfilestofile    = Convert Query stored in *.SQL Files will be spooled to an output file
        sqlcmdtoconsole   = Convert Query on SQLQuery will be displayed on console
        sqlfilestofiles   = Convert Query stored in *.SQL Files will be spooled to output files *.SQL
        sqlfilestoconsole = Convert Query stored in *.SQL files will be displayed on console

        Required?                    false
        Position?                    5
        Default value
        Accept pipeline input?       false
        Accept wildcard characters?  false

    -SpoolFile <String>

        Required?                    false
        Position?                    6
        Default value
        Accept pipeline input?       false
        Accept wildcard characters?  false

    <CommonParameters>
        This cmdlet supports the common parameters: Verbose, Debug,
        ErrorAction, ErrorVariable, WarningAction, WarningVariable,
        OutBuffer, PipelineVariable, and OutVariable. For more information, see
        about_CommonParameters (https:/go.microsoft.com/fwlink/?LinkID=113216).

INPUTS

OUTPUTS

    -------------------------- EXAMPLE 1 --------------------------

    PS C:\>.\runSSMA.ps1 -Mode all






    -------------------------- EXAMPLE 2 --------------------------

    PS C:\>.\runSSMA.ps1 -Mode querydb -SQLQuery "select table_name from dba_tables where owner='THEOWNER'"

</pre>

# Assessing multiple Oracle Databases
See config.ini file section [sourcedb], [targetdb], [db1], [db2],....[dbn]

<pre>

#this is general parameters
[general]
object-overwrite=skip
encrypted-password=true
workingdirectory=c:\ssmaoutput
xmloutput=c:\bram-ssma
#fatal-error,error,warning,info,debug
logverbosity=error
#max db=3 this can be as many as you like
maxdbs=3

#this are parameters for assessment
[assessment]
reportmessage=false
reportprogress=every-10%
suppressmessage=false
#ask-user,continue,error
userinputpopup=continue
upgradeproject=yes
enableprogressreporting=true
prereqstrictmode=false
#fatal-error,error,warning,info,debug
logverbosity=debug

#the following parameters apply to all databases, unless specific [dbn] is available, so [dbn] will take precedence
[alldb]
reportfolder=Assessmentreport
convertedsql=sqloutput
sourcesql=sourcesql
savescript=savescript
#onpremwinauth,onpremsqlauth,azuresqldb,azuresqlmi,azuresynapse
targetplatform=azuresynapse
projectname=OracleToSynapse
#sql-server-2012,sql-server-2014,sql-server-2016,sql-server-2017,sql-server-2019,sql-azure,sql-azure-mi,sql-azure-dw
projecttype=sql-azure-dw
projectoverwrite=true
#report-total-as-warning,report-each-as-warning,fail-script
synctargetonerror=report-each-as-warning
refreshdbonerror=report-each-as-warning
#all,single,category
object=single
#if object=catagory, then objecttype=Tables,Views,Procedures...(if objecttype not specified then default=Procedures)
objecttype=Procedures
#current_schema,SYS.object_#n
#objtocollect=

#ssma wlil ONLY perform datamigration and assessment on for db1 on object tables, 
#the [alldb] config above will be overriden by any parameter that are available under [dbn]
[db1]
object=single
datamigration=true
objecttype=tables

#this db will be skipped as the enabled is set to false
[db2]
enabled=false
object=single
objecttype=procedures

#ssma will ONLY peform conversion and assessment for db3 on object views
[db3]
enabled=true
object=single
objecttype=views

[sourcedb]
db1=192.168.0.178,1519,TEST,system,manager,HR
db2=10.1.66.233,1523,ORAPROD,READ_ONLY,readonly,BIPROD
db3=10.1.66.253,1521,ORACOGNOS,READ_ONLY,readonly,BICOGNOS

[targetdb]
db1=azuredb1.database.windows.net,1433,DBDEV,dataloader,godkn0ws,BIXDEV
db2=azuredb2.database.windows.net,1433,DBPROD,sqladmin,secret,BIXPROD
db3=azuredb3.database.windows.net,1433,DBCOGNOS,sqladmin,password,cognos


</pre>
