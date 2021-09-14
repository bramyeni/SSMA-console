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

