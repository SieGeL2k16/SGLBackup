#  SGLBackup.pl - English Documentation
Last  Update on August 12th, 2008

SGLBackup is a small perlscript that is able to back up directories or
MySQL and Oracle databases.
This script was mainly programmed for my private purposes to have an easy
and fully automatic process to back up my own created Websites and databases.
Development was always focused to have less work as possible with the whole
backup process, the only thing I have to do manually is burning the backups
on CDs every weekend.

## The script has the following features:

- Unlimited amount of filesystem backups (per Directory)
- Unlimited amount of MySQL Backups (via mysqldump)
- Unlimited amount of Oracle Backups (via Oracle Export utility)
- Support for gzip or bzip2 to compress the tar()ed files.
- Backups can be copied to either locally mounted filesystems or via
  FTP to remote destination hosts.
- Easy configuration with an "Ini-Style" configuration file.
- Support for wildcards as directory entries. (V0.38+)
- Support for wildcards as MySQL Database names (V0.39+)
- Support for auto-created target directories based on input dirs (V0.41+)
- Free :-)

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! IMPORTANT !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

I TAKE NO RESPONSIBILITY FOR THE RELIABILITY OF THE CREATED BACKUPS - THIS
IS UP TO YOU THE USER OF THIS SCRIPT!
I HAVE NEVER EXPIERENCED ANY DATA CORRUPTION DURING THE TIME, BUT WE ALL
KNOW THAT NO SOFTWARE IS 100% BUG-FREE. YOU ARE USING THIS SCRIPT ON YOUR
OWN RISK!

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! IMPORTANT !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


## INSTALLATION AND CONFIGURATION

Before you can use this script you have to check the requirements as listed
below:

#### a) Perl modules

The script requires the following perl modules:

FindBin
Config::IniFiles
Getopt::Long
Pod::Usage
Time::HiRes
Net::FTP
File::Copy
File::Basename

A lot of these modules are already part of the perl core distribution, all
others could be downloaded from www.cpan.org.

#### b) 3rd-Party tools:

Most of the functionality of SGLbackup relies on 3rd-Party tools, which
are currently the following:

 - Tar (GNU Tar!) for creating the backup files.
 - GZip or BZip2 to compress the tar files.
 - Mysqldump (If you plan to backup MySQL databases)
 - Oracle Export (If you plan to backup Oracle databases)
 - Scp/Ssh executables to send files via SCP.

At least "tar" and one of the packers (either "gzip" or bzip2")
must be configured, everything else is optional and up to you.

Configuration of SGLBackup is done via a plain textfile, which
is per default named as ```config.ini``` and searched in the current
directory.
You can use the # sign for comments. Parameters are always
given in the following form:

```key = value```

These keywords are grouped in sections for better overview.
Section names are enclosed in square brackets [] and all
according keywords have to follow after the section name.

Currently, the following keywords and sections are known to
SGLBackup:

### Section [COMMAND]


#### TAR = /usr/local/bin/tar

Defines the full path to your tar program.


#### TAROPTS = -chf

Defines the parameter used to call TAR. If this parameter is not given
SGLBackup uses "-chf" as default parameter (V0.39+).


#### GZIP = /usr/bin/gzip --fast --force

Defines the full path to your favourite packer program
INCLUDING all options required for your packer to force the
packer to overwrite existing files (i.e. --force) and which
packing ratio should be used (i.e. --best).

#### GZIP_EXT = .gz

Define here which extension your choosen packer uses, i.e. gzip
uses *.gz while bzip2 use *.bz2. This is required to handle
the created files correctly!


#### TMPDIR = /wd/temp

You may specify a directory the script should use as temporary
directory. If you leave out this parameter the script tries to
use /tmp.


#### LOGFILE = /export/home/siegel/SGLBackup/sglbackup.log
Specify here a full pathname where you want the logfile to be written to.
If you need no logfile remove this parameter.

#### MYSQLDUMP = /usr/local/mysql/bin/mysqldump

Specify here where to find the "mysqldump" utility that is used to back up
MySQL Databases. If this parameter is not given MySQL support is disabled.
Available since V0.33.


#### MYSQLDUMPOPTS = --routines --trigger

Specify here additional options to be passed to mysqldump. The parameter listed
here in this example enable exporting of internal routines/functions and
triggers, which are all supported since MySQL V5.x.

Available since V0.40.


#### MKNOD = /bin/mknod

Defines the full path to the "mknod" executable, which is used to create
named pipes. This is only neccessary if you plan to use the VLDB mode of
SGLBackup (see section "BACKUP_SETS for more information).


#### MAIL_CMD = /usr/bin/printf "%b" "{BODY_TEXT}" | /bin/mail -s "{SUBJECT}" your@email.com

Specifies the mail command to be executed whenever an error occured. Will
replace {BODY_TEXT} with the corresponding error messages and {SUBJECT} with
the generated email subject.

Available since V0.40.


### Section [BACKUP_SETS]

#### DIR_\<x\> = /html/testpath1

Defines the directory to back up for backup set <x>.
This is a multimode parameter as you can either define here a
full path to a directory to back up or specify special
keywords to define Database backups. Format is as follows:

 - If a complete pathname (starting with a '/') is given
   this directory will be completly backupped.

 - If either ORACLE: or MYSQL: stands as first keyword
   database backup mode is choosen. The format of these
   strings is for Oracle:

 ```ORACLE:<username>/<password>@<tnsname>|<schema>```

 or for MySQL

 ```MYSQL:<username>/<password>@<hostname>|<database>```

 If you omit the schema or database parameter the whole
 database will be exported. In both cases the according
 tool of your database vendor is called, for Oracle this
 is ***$ORACLE_HOME/bin/exp*** while for MySQL it is determined
 from the configuration file (parameter MYSQLDUMP).

 Since V0.39 it is possible to enter a wildcard as MySQL Database name,
 this would look like this:

 ```MYSQL:<username>/<password>@<hostname>|*```

 This would result in backuping ALL databases of the given MySQL DB,
 one file per found database.

 ```MYSQL:<username>/<password>@<hostname>|test*```

 Would only back up databases with names starting with "test"

 See examples below.

If you have given a directory path make sure that the user under
which SGLBackup is running has proper permissions to read the
target directory, else the backup won't work!

Since V0.38 you can also add wildcards (aka patterns) as directory names,
so if you use i.e.

```DIR_0 = /html/php*```

SGLBackup will then scan the /html folder and add all matching php* directory
entries as own configuration entries. There are a number of restrictions
when using patterns, see end of docs for further information about using this
mode.


#### NAME_\<x\> = TESTBACKUP

Name for given backupset. Please use characters that are suitable
to be used inside a filename, as SGLBackup creates backupfiles with this
name as prefix!

Also, when using wildcards for directories this name is used as prefix, the
found directory name is append with an underscore to that prefix here.


#### MODE_\<x\> = FCOPY,FTP

Here you have to specify how the backup file should be transported
to your backup device, currently FCOPY and FTP are supported.

If you use i.e. an external hard disc that is mounted, you may use
FCOPY (FileCopy) as mode and have to enter a valid destination
directory with write access under the corresponding
```DEST_<x>``` parameter.

You may also use FTP as mode, in this case you have to enter valid
logindata with the ```FTP_<x>``` parameter.

Since V0.41 you can also use the SCP option to use SecureCoPy (SSH).

You can also combine both parameter, i.e.

```MODE_0 = FTP,FCOPY```

would copy the backupfile both to the destination directory and
to the given FTP host.


#### FTP_\<x\> = user:pass@host
If you have FTP mode choosen, you have to enter here the logindata
for your backup FTP Server to use. The format is:

USER:PASSWORD@HOST:PORT

If your server listens on standard port 21 you can leave out the PORT
parameter.


#### FTP_DEST_\<x\> = /

This specifies the directory on the FTP server where backupfiles should
be stored. Please make sure that SGLBackup has write permissions on that
target directory!


#### DEST_\<x\> = /backups

This is the destination directory when using the FCOPY mode. Please make
sure that write permissions are correctly set.


#### MAXGEN_\<x\> = 7

If this is set SGLBackup checks after backup if more files are stored
on target than defined here. In this case the oldest files are removed
until the maximum amount of files is reached. If this parameter is not
set SGLBackup skips checking. This allows to have a fixed amount of backups
available.


#### VLDB_\<x\> = <yes|no>

This parameter affects how SGLBackup behaves on Oracle backups. Normally
SGLBackup exports Oracle databases with the help of the exp utility by
writing the given schema including the logfile to the configured temporary
directory, creates afterwards a TAR archive and crunches it finally with
the configured packer.
However, if your Oracle DB contains very large databases you may end up with
a full disc as this mode of operation requires at least double the size of
your exported schema available on your configured directory. If this is not
possible during large schemata you can enable this parameter (set it to yes),
in this case SGLBackup creates via the "MKNOD" parameter a named pipe and
sends the export file via this pipe directly to the configured packer. This
reduces the required disk space to the size of the final crunched exportfile.
Drawback on this method however is the fact that no logfile is added to the
export and on multi-cpu systems you may notice a higher workload as both
packer and Oracle Export utils are running in parallel.

To use this feature you have to configure also the parameter

```MKNOD = <path_to_mknod_executable>```

and of course set ```VLDB_<x> = YES```


#### SCP_\<x\> = USER@HOST:TARGETDIRECTORY

Logindata when using SCP mode. Format is ```USER@HOST:TARGETDIRECTORY```.


#### SCP_OPTS_\<x\>


Optional additional parameter for SCP to use (i.e. "-i identityfile")


See ```configs/config.ini.dist``` for an example configuration file.


HOW TO USE THE SCRIPT

If you call the script without any parameter SGLBackup performs backups
on all configured sets. You can also pass some parameter to the script to
modify the behavour. The following parameters are known to the script:

--help         Brief help message

--man          full documentation

--config       Alternative configfile (default is config.ini)

--backupset    Number(s) of backupset to process (default is all)

--showconfig   Lists parsed configuration and exit

--checkgen     Performs checks on available generations

To perform a backup on backupsets 0,1,2 and 4:

```$> ./SGLBackup.pl --backupset=0,1,2,4```

To show the configuration after parsing it:

```$> ./SGLBackup.pl --showconfig```

Checking amount of available backupfiles on targets for all sets:

```$> ./SGLBackup.pl --checkgen```

Checking amount of available backupfiles on targets for backup sets 0 and 4:

```$> ./SGLBackup.pl --backupset=0,4 --checkgen```

Not that hard IMO to use :)


## SOME EXAMPLES FOR DATABASE BACKUPS

### For MySQL:

Make backup of database "GP4RL" on host "localhost" with username
"scott" and password "tiger":

```DIR_<x> = MYSQL:scott/tiger@localhost|GP4RL```

Complete backup of a MySQL database as user "root" on host "192.168.255.8"
without a password (hopefully nobody does this!!!):

```DIR_<x> = MYSQL:root/@localhost```


### For Oracle:

IMPORTANT: As this script utilises the "exp" utility from the Oracle
installation it is required that you have either the Server or the
client fully installed, the instant client is not enough as it lacks
the export util! Also make sure that the "ORACLE_HOME" environment
variable is correctly set!

Export of schema "SCOTT" from TNSHost "NETRA" using DBA account
"SYSTEM" with password "MANAGER":

```DIR_<x> = ORACLE:SYSTEM/MANAGER@NETRA|SCOTT```

Export of complete database on TNSHost "NETRA" using DBA account
"SYSTEM" with password "MANAGER":

```DIR_<x> = ORACLE:SYSTEM/MANAGER@NETRA```

Export of schema "ORAOFFICE" without using a TNSName (local database)
using the schema owner "ORAOFFICE" with password "ORAPW":

```DIR_<x> = ORACLE:ORAOFFICE/ORAPW|ORAOFFICE```


## SOME NOTES ON PATTERNS (aka WILDCARDS)

Since V0.38 SGLBackup now supports wildcards for directory names
and MySQL Databases.
This allows i.e. to back up hundreds of directories with a simple
configuration entry, a feature that maybe useful to providers
to back up their customer directories. 

However, there are some restrictions when working on this mode:

- The pattern match (currently) only supports the '*' sign as LAST (!)
  character in the directory definition. So the following is ok:

  ```/html/*```

  but this one is not okay:

  ```/html/test*me```

  Note that SGLBackup won't find the latter, so make sure that the
  '*' sign is really the last character.

- You cannot choose backupsets when using patterns, so you can only
  create "full backups". The reason is that the script resolves the
  pattern internally and adds all found directories as own config
  settings, which results in far more entries than configured by the user.
  If you pass a given backupset number and have ALSO configured
  wildcards in the same configuration SGLBackup will exit with an
  error message.

- All matched directories are sharing the same copy mode (FTP/FCOPY),
  the same logindata for FTP and also the same amount of max. allowed
  generations.

- The name of the config set that defines the pattern is used as prefix
  for all matching directories.

To illustrate the usage of this new feature, here is a small configset
which I've used to test the functionality:

```
[BACKUP_SETS]

DIR_0       = /html/*
NAME_0      = html_auto
MODE_0      = FCOPY
DEST_0      = /wd/tests
MAXGEN_0    = 7

DIR_1       = MYSQL:root/root@localhost|*
NAME_1      = MySQL_auto
MODE_1      = FCOPY
DEST_1      = /wd/tests
MAXGEN_1    = 7
```

This config setting, when shown via "--showconfig" option, results in:

```
Configured backup sets:

Backupset number (name)..: 0 (html_auto)
Backup source............: /html/*
Target destination.......: FCOPY: /wd/tests
Defines pattern match....: Yes

Backupset number (name)..: 1 (html_auto_Boinc-Stats)
Backup source............: /html/Boinc-Stats
Target destination.......: FCOPY: /wd/tests
Defines pattern match....: No

Backupset number (name)..: 2 (html_auto_CS)
Backup source............: /html/CS
Target destination.......: FCOPY: /wd/tests
Defines pattern match....: No
```
...and ~90 other directories and additional all MySQL entries:
```
Backupset number (name)..: 95 (MySQL_auto_F1)
Backup source............: MYSQL:root/root@localhost|F1
Target destination.......: FCOPY: /wd/tests
Defines pattern match....: No
Backup using named pipe..: No

Backupset number (name)..: 96 (MySQL_auto_GP4RL)
Backup source............: MYSQL:root/root@localhost|GP4RL
Target destination.......: FCOPY: /wd/tests
Defines pattern match....: No
Backup using named pipe..: No
```

As you can see from the output the name of the defining pattern is used as
prefix for all found directories and databases, and all matching entries
share the same data as the defining pattern. Also note that the defined
pattern entry is of course skipped when running the script, only entries
with the setting "Defines pattern match = No" are backupped.

I highly recommend to use a separate configuration file when using patterns
and pass this configfile to SGLBackup via the "--config" parameter.
Also make sure that you control the correct usage of patterns with the
"--showconfig" parameter first, it will show you all matching directories
as you can see in the example above.
